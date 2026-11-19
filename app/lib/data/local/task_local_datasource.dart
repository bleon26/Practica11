import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../sync/conflict_resolver.dart';
import '../models/task.dart';
import 'app_database.dart';

/// Resumen de una fase MERGE.
class MergeStats {
  const MergeStats({this.inserted = 0, this.overwritten = 0, this.keptLocal = 0});
  final int inserted;
  final int overwritten;
  final int keptLocal;

  int get total => inserted + overwritten + keptLocal;

  MergeStats operator +(MergeStats o) => MergeStats(
        inserted: inserted + o.inserted,
        overwritten: overwritten + o.overwritten,
        keptLocal: keptLocal + o.keptLocal,
      );

  @override
  String toString() => 'MergeStats(+$inserted, ~$overwritten, local=$keptLocal)';
}

/// Acceso a SQLite. La UI **solo** lee de aquí (Streams locales) — nunca de la red.
class TaskLocalDataSource {
  TaskLocalDataSource(this._appDb);

  final AppDatabase _appDb;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Future<Database> get database => _appDb.database;

  /// Notifica a los Streams que la tabla cambió.
  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // ------------------------------------------------------------- Streams UI
  /// Lista reactiva de tareas visibles (no borradas). Emite al suscribirse y
  /// en cada escritura local o merge remoto.
  Stream<List<Task>> watchTasks() => _watch(getVisibleTasks);

  /// Número de registros con `is_synced = 0` (para el indicador visual).
  Stream<int> watchPendingCount() => _watch(countPending);

  Stream<T> _watch<T>(Future<T> Function() query) {
    late final StreamController<T> controller;
    StreamSubscription<void>? sub;

    Future<void> emit() async {
      try {
        final value = await query();
        if (!controller.isClosed) controller.add(value);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  // ------------------------------------------------------- Paso 3: escritura
  /// Guarda primero en disco, sin esperar red, con bandera sucia `is_synced = 0`.
  Future<void> saveLocal(Task t) async {
    final db = await database;
    await db.insert(
      'tasks',
      t.toMap(isSynced: 0),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChanged(); // respuesta instantánea en la UI
  }

  // ---------------------------------------------------------------- Lecturas
  Future<List<Task>> getVisibleTasks() async {
    final db = await database;
    final rows = await db.query('tasks', where: 'is_deleted = 0', orderBy: 'updated_at DESC');
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> getById(String id) async {
    final db = await database;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  /// Registros pendientes de subir (incluye borrados lógicos).
  Future<List<Task>> getPending() async {
    final db = await database;
    final rows = await db.query('tasks', where: 'is_synced = 0', orderBy: 'updated_at ASC');
    return rows.map(Task.fromMap).toList();
  }

  Future<int> countPending() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tasks WHERE is_synced = 0')) ?? 0;
  }

  // ------------------------------------------------------------- Sync (ACK)
  /// Paso 6 · ACK: marca `is_synced = 1` **solo si** el registro no se editó
  /// mientras viajaba a la nube (mismo `updated_at` que se envió). Si el
  /// usuario lo modificó durante el PUSH, sigue pendiente.
  Future<bool> markSynced(String id, {required String sentUpdatedAt, required int version}) async {
    final db = await database;
    final count = await db.update(
      'tasks',
      {'is_synced': 1, 'version': version},
      where: 'id = ? AND updated_at = ?',
      whereArgs: [id, sentUpdatedAt],
    );
    return count == 1;
  }

  // ----------------------------------------------------------- Sync (MERGE)
  /// Paso 6 · MERGE: integra registros remotos dentro de UNA transacción,
  /// resolviendo cada colisión con [ConflictResolver] (LWW por updated_at).
  /// Al hacerlo en transacción, una edición del usuario no puede colarse
  /// entre la lectura y la escritura.
  Future<MergeStats> mergeRemote(List<Task> remote) async {
    if (remote.isEmpty) return const MergeStats();
    final db = await database;
    var stats = const MergeStats();

    await db.transaction((txn) async {
      for (final r in remote) {
        final rows = await txn.query('tasks', where: 'id = ?', whereArgs: [r.id], limit: 1);
        final local = rows.isEmpty ? null : Task.fromMap(rows.first);

        switch (ConflictResolver.resolve(local: local, remote: r)) {
          case MergeDecision.insertRemote:
            await txn.insert('tasks', r.toMap(isSynced: 1), conflictAlgorithm: ConflictAlgorithm.replace);
            stats += const MergeStats(inserted: 1);
          case MergeDecision.overwriteWithRemote:
            await txn.insert('tasks', r.toMap(isSynced: 1), conflictAlgorithm: ConflictAlgorithm.replace);
            stats += const MergeStats(overwritten: 1);
          case MergeDecision.keepLocal:
            stats += const MergeStats(keptLocal: 1);
        }
      }
    });

    notifyChanged();
    return stats;
  }

  /// Elimina físicamente los borrados lógicos que la nube ya confirmó.
  Future<int> purgeSyncedTombstones() async {
    final db = await database;
    return db.delete('tasks', where: 'is_deleted = 1 AND is_synced = 1');
  }

  // ------------------------------------------------------------- Metadatos
  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert('sync_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ----------------------------------------------------- Limpieza de sesión
  /// Purga TODA la información local (cerrar sesión / cambio de usuario).
  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tasks');
      await txn.delete('sync_meta');
    });
    notifyChanged();
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
