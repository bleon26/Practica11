import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_tasks/data/local/app_database.dart';
import 'package:offline_first_tasks/data/local/task_local_datasource.dart';
import 'package:offline_first_tasks/data/models/task.dart';
import 'package:offline_first_tasks/data/remote/api_client.dart';
import 'package:offline_first_tasks/data/repositories/task_repository.dart';
import 'package:offline_first_tasks/sync/sync_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_remote.dart';

/// Reproduce en pruebas automáticas los "Escenarios Obligatorios de Prueba"
/// de la práctica usando SQLite real (FFI) y un backend en memoria.
void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late String dbPath;
  late AppDatabase db;
  late TaskLocalDataSource local;
  late FakeRemote remote;
  late SyncRepository sync;
  late TaskRepository repo;

  Future<void> openAll() async {
    db = AppDatabase(factory: databaseFactoryFfi, path: dbPath);
    local = TaskLocalDataSource(db);
    sync = SyncRepository(local: local, remote: remote);
    repo = TaskRepository(local: local, onLocalChange: () {});
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_first_test_');
    dbPath = p.join(tmp.path, 'test.db');
    remote = FakeRemote();
    await openAll();
  });

  tearDown(() async {
    await local.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('Paso 3: saveLocal persiste con is_synced = 0 y el Stream emite al instante', () async {
    final emissions = <List<Task>>[];
    final sub = local.watchTasks().listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await repo.create(title: 'Primera');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(emissions.last.single.title, 'Primera');
    expect(emissions.last.single.isSynced, isFalse);
    expect(await local.countPending(), 1);
    await sub.cancel();
  });

  test('Escenario 1 · Modo avión: crear y editar 3 registros offline sin pérdida', () async {
    remote.offline = true;

    final a = await repo.create(title: 'A');
    final b = await repo.create(title: 'B');
    final c = await repo.create(title: 'C');
    await repo.update(a, title: 'A editada');
    await repo.toggleDone(b);
    await repo.update(c, description: 'detalle offline');

    await expectLater(sync.sync(), throwsA(isA<NetworkException>()));
    expect(sync.status.value.phase, SyncPhase.error);

    final tasks = await local.getVisibleTasks();
    expect(tasks, hasLength(3));
    expect(tasks.every((t) => !t.isSynced), isTrue);
    expect(tasks.map((t) => t.title), containsAll(['A editada', 'B', 'C']));
    expect(remote.store, isEmpty);
  });

  test('Escenario 2 · Cierre forzado: los cambios sobreviven al reiniciar la app', () async {
    remote.offline = true;
    await repo.create(title: 'Persistente 1');
    await repo.create(title: 'Persistente 2');

    // "Matar" la app: cerrar conexión y descartar todos los objetos.
    await local.dispose();
    await db.close();

    // "Reabrir" la app sobre el mismo archivo .db
    await openAll();
    final tasks = await local.getVisibleTasks();
    expect(tasks.map((t) => t.title), containsAll(['Persistente 1', 'Persistente 2']));
    expect(await local.countPending(), 2);
  });

  test('Escenario 3 · Reconexión: PUSH + ACK suben todo y limpian la bandera', () async {
    remote.offline = true;
    for (final title in ['Uno', 'Dos', 'Tres']) {
      await repo.create(title: title);
    }
    expect(await local.countPending(), 3);

    remote.offline = false; // vuelve la señal
    final report = await sync.sync();

    expect(report.push.acked, 3);
    expect(remote.store.values.map((t) => t.title), containsAll(['Uno', 'Dos', 'Tres']));
    expect(await local.countPending(), 0);
    expect((await local.getVisibleTasks()).every((t) => t.isSynced && t.version == 1), isTrue);
  });

  test('ACK condicional: si el usuario edita durante el PUSH, sigue pendiente', () async {
    final t = await repo.create(title: 'original');
    final sent = (await local.getPending()).single;
    await repo.update(t, title: 'editada mientras viajaba');

    final acked = await local.markSynced(sent.id, sentUpdatedAt: sent.updatedAt, version: 1);
    expect(acked, isFalse);
    expect(await local.countPending(), 1);
  });

  test('Idempotencia: reenviar tras perder el ACK no duplica en la nube', () async {
    await repo.create(title: 'una sola vez');
    final pending = await local.getPending();
    await remote.pushTasks(pending); // llegó a la nube pero el ACK se perdió
    final second = await remote.pushTasks(pending);

    expect(second.single.status, 'duplicate');
    expect(remote.store, hasLength(1));
    await sync.sync();
    expect(await local.countPending(), 0);
  });

  test('PULL + MERGE: cambios de otro dispositivo llegan y se marcan sincronizados', () async {
    final otherDevice = Task.create(title: 'Desde la tablet');
    remote.serverWrite(otherDevice);

    final report = await sync.sync();
    expect(report.pull.inserted, 1);
    final local1 = await local.getById(otherDevice.id);
    expect(local1!.isSynced, isTrue);
    expect(local1.version, 1);

    // Segundo pull no trae nada (cursor incremental)
    expect((await sync.sync()).pull.total, 0);
  });

  test('Colisión LWW: la edición remota más reciente gana sobre la local pendiente', () async {
    final t = await repo.create(title: 'base');
    await sync.sync();
    final synced = (await local.getById(t.id))!;

    remote.offline = true;
    await repo.update(synced, title: 'local (antes)'); // edición offline
    final localEdit = (await local.getById(t.id))!;

    // Otro dispositivo edita DESPUÉS en la nube
    remote.serverWrite(localEdit.copyWith(
      title: 'remota (después)',
      updatedAt: DateTime.parse(localEdit.updatedAt).add(const Duration(minutes: 1)).toIso8601String(),
    ));

    remote.offline = false;
    final report = await sync.sync();
    expect(report.push.rejected, 1);
    expect((await local.getById(t.id))!.title, 'remota (después)');
    expect(await local.countPending(), 0);
  });

  test('Colisión LWW: la edición local más reciente gana y sube a la nube', () async {
    final t = await repo.create(title: 'base');
    await sync.sync();
    final synced = (await local.getById(t.id))!;

    // Otro dispositivo edita primero…
    remote.serverWrite(synced.copyWith(title: 'remota (antes)'));
    // …y este dispositivo edita después.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.update(synced, title: 'local (después)');

    final report = await sync.sync();
    expect(report.push.acked, 1);
    expect(remote.store[t.id]!.title, 'local (después)');
    expect(remote.store[t.id]!.version, 3);
    expect((await local.getById(t.id))!.isSynced, isTrue);
  });

  test('Soft delete: se propaga a la nube y luego se purga localmente', () async {
    final t = await repo.create(title: 'borrar');
    await sync.sync();
    await repo.delete((await local.getById(t.id))!);

    expect(await local.getVisibleTasks(), isEmpty);
    expect(await local.getById(t.id), isNotNull, reason: 'tombstone hasta confirmar');

    await sync.sync();
    expect(remote.store[t.id]!.isDeleted, isTrue);
    expect(await local.getById(t.id), isNull, reason: 'purgado tras confirmación');
  });

  test('Limpieza de sesión: clearAll purga tareas y cursor', () async {
    await repo.create(title: 'privada');
    await local.setMeta(SyncRepository.cursorKey, '42');
    await local.clearAll();
    expect(await local.getVisibleTasks(), isEmpty);
    expect(await local.getMeta(SyncRepository.cursorKey), isNull);
  });
}
