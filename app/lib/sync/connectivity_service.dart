import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Paso 4 · Escucha reactiva de la red con connectivity_plus.
///
/// - Stream continuo: monitorea Wi-Fi / datos móviles.
/// - Disparo automático: al recuperar señal ejecuta la cola pendiente.
/// - Indicador visual: expone [online] para el banner offline de la UI.
///
/// Nota: "hay interfaz de red" no garantiza "hay internet"; si la petición
/// falla, el cambio sigue en SQLite y WorkManager lo reintentará.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;

  static bool isOnlineResult(List<ConnectivityResult> res) =>
      res.isNotEmpty && !res.contains(ConnectivityResult.none);

  Future<void> start({required void Function() onReconnect}) async {
    await stop();
    final initial = await _connectivity.checkConnectivity();
    online.value = isOnlineResult(initial);
    if (online.value) onReconnect();

    _sub = _connectivity.onConnectivityChanged.listen((res) {
      final wasOnline = online.value;
      final isOnline = isOnlineResult(res);
      online.value = isOnline;
      if (isOnline && !wasOnline) {
        onReconnect(); // syncRepository.pushPending() + pull
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    online.dispose();
  }
}
