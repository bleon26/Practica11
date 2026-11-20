import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Abre (y crea/migra) la base SQLite local: la **fuente única de verdad**.
class AppDatabase {
  /// [singleInstance] = `false` abre una conexión nativa propia. Lo usa el
  /// isolate de WorkManager: en Android sqflite comparte por defecto una sola
  /// conexión por archivo en todo el proceso, y su `close()` cerraría también
  /// la de la UI (`DatabaseException(database_closed)`).
  AppDatabase({DatabaseFactory? factory, String? path, bool singleInstance = true})
      : _factory = factory,
        _path = path,
        _singleInstance = singleInstance;

  static const fileName = 'offline_first.db';
  static const schemaVersion = 1;

  final DatabaseFactory? _factory;
  final String? _path;
  final bool _singleInstance;
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path = _path ?? p.join(await factory.getDatabasesPath(), fileName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _onCreate,
        singleInstance: _singleInstance,
      ),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Paso 2: tabla con metadatos de sincronización.
    await db.execute('''
      CREATE TABLE tasks (
        id          TEXT PRIMARY KEY,
        title       TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        is_done     INTEGER NOT NULL DEFAULT 0,
        is_synced   INTEGER DEFAULT 0,
        updated_at  TEXT NOT NULL,
        is_deleted  INTEGER DEFAULT 0,
        version     INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_tasks_is_synced ON tasks(is_synced)');

    // Metadatos del motor de sync (cursor del último PULL).
    await db.execute('''
      CREATE TABLE sync_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
