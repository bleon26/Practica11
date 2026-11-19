import 'dart:async';
import 'dart:developer' as dev;

import '../data/local/app_database.dart';
import '../data/local/task_local_datasource.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/secure/token_storage.dart';
import '../sync/background_sync.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_repository.dart';
import 'config.dart';

/// Raíz de composición: crea y conecta todas las capas.
///
///   UI  ⇄  SQLite (fuente única de verdad)  ⇄  Backend cloud (segundo plano)
class AppServices {
  AppServices._({
    required this.db,
    required this.local,
    required this.api,
    required this.auth,
    required this.sync,
    required this.connectivity,
  }) {
    tasks = TaskRepository(local: local, onLocalChange: _onLocalChange);
  }

  static Future<AppServices> create() async {
    final db = AppDatabase();
    final local = TaskLocalDataSource(db);
    final tokens = TokenStorage();

    late final AuthRepository auth;
    final api = ApiClient(tokenProvider: () => auth.currentToken());
    auth = AuthRepository(api: api, tokens: tokens, local: local);
    final sync = SyncRepository(local: local, remote: api);

    final services = AppServices._(
      db: db,
      local: local,
      api: api,
      auth: auth,
      sync: sync,
      connectivity: ConnectivityService(),
    );
    await auth.restore();
    if (auth.session.value != null) await services.onSignedIn();
    return services;
  }

  final AppDatabase db;
  final TaskLocalDataSource local;
  final ApiClient api;
  final AuthRepository auth;
  final SyncRepository sync;
  final ConnectivityService connectivity;
  late final TaskRepository tasks;

  Timer? _debounce;

  /// Arranca los disparadores de sync al tener sesión.
  Future<void> onSignedIn() async {
    await connectivity.start(onReconnect: () => unawaited(syncNow()));
    await BackgroundSync.schedulePeriodic();
  }

  /// Ejecuta un ciclo PUSH/ACK/PULL/MERGE si hay red. Nunca lanza: los
  /// errores quedan en `sync.status` y los datos siguen seguros en SQLite.
  Future<void> syncNow() async {
    if (auth.session.value == null || !connectivity.online.value) return;
    try {
      await sync.sync();
    } on UnauthorizedException {
      await auth.expire();
    } catch (e) {
      dev.log('syncNow: $e', name: 'sync');
    }
  }

  /// Cada escritura local: (1) agenda WorkManager para que suba aunque la
  /// app se cierre y (2) si hay red, sincroniza en primer plano con debounce.
  void _onLocalChange() {
    unawaited(BackgroundSync.scheduleOneOff());
    _debounce?.cancel();
    _debounce = Timer(AppConfig.syncDebounce, () => unawaited(syncNow()));
  }

  /// Al volver a primer plano: refresca la UI (el isolate de WorkManager pudo
  /// escribir en SQLite) y sincroniza.
  Future<void> onResumed() async {
    local.notifyChanged();
    await syncNow();
  }

  Future<void> logout() async {
    _debounce?.cancel();
    await connectivity.stop();
    await BackgroundSync.cancelAll();
    await auth.logout();
    sync.status.value = const SyncStatus();
  }
}
