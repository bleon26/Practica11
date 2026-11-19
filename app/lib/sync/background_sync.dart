import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/app_database.dart';
import '../data/local/task_local_datasource.dart';
import '../data/remote/api_client.dart';
import '../data/secure/token_storage.dart';
import 'sync_repository.dart';

const kSyncTaskName = 'bidirectionalSync';
const kOneOffUniqueName = 'sync-task-id';
const kPeriodicUniqueName = 'periodic-sync';

/// Punto de entrada del isolate de segundo plano. Se ejecuta aunque la app
/// esté cerrada (Android WorkManager lo arranca cuando se cumplen las
/// restricciones, p. ej. red conectada).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundSync();
  });
}

/// Devuelve `true` si terminó (con o sin cambios) y `false` para que
/// WorkManager reintente con backoff exponencial.
Future<bool> runBackgroundSync() async {
  final tokens = TokenStorage();
  final session = await tokens.readSession();
  if (session == null) return true; // sin sesión: nada que sincronizar

  final db = AppDatabase();
  final local = TaskLocalDataSource(db);
  final api = ApiClient(baseUrl: await tokens.readApiUrl(), tokenProvider: () async => session.token);
  try {
    await SyncRepository(local: local, remote: api).sync();
    return true;
  } on UnauthorizedException {
    await tokens.clearToken(); // token expirado: se pedirá login, datos intactos
    return true;
  } catch (_) {
    return false; // red inestable / servidor caído -> reintentar
  } finally {
    api.close();
    await local.dispose();
    await db.close();
  }
}

/// Paso 5 · Ejecución diferida con WorkManager.
class BackgroundSync {
  const BackgroundSync._();

  static bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> initialize() async {
    if (!isSupported) return;
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Tarea única tras cada escritura local: corre en cuanto haya red, aunque
  /// el usuario cierre la app. `replace` es seguro porque el ciclo es idempotente.
  static Future<void> scheduleOneOff() async {
    if (!isSupported) return;
    await Workmanager().registerOneOffTask(
      kOneOffUniqueName,
      kSyncTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  }

  /// Red de seguridad: sync periódico (mínimo 15 min impuesto por Android).
  static Future<void> schedulePeriodic() async {
    if (!isSupported) return;
    await Workmanager().registerPeriodicTask(
      kPeriodicUniqueName,
      kSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancelAll() async {
    if (!isSupported) return;
    await Workmanager().cancelAll();
  }
}
