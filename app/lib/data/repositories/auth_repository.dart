import 'package:flutter/foundation.dart';

import '../local/task_local_datasource.dart';
import '../remote/api_client.dart';
import '../secure/token_storage.dart';

class AuthRepository {
  AuthRepository({required this.api, required this.tokens, required this.local});

  final ApiClient api;
  final TokenStorage tokens;
  final TaskLocalDataSource local;

  /// Sesión actual (null = mostrar login).
  final ValueNotifier<AuthSession?> session = ValueNotifier<AuthSession?>(null);

  Future<String?> currentToken() async => session.value?.token;

  Future<void> restore() async {
    session.value = await tokens.readSession();
  }

  Future<void> login(String username, String password) => _start(api.login(username, password));

  Future<void> register(String username, String password) => _start(api.register(username, password));

  Future<void> _start(Future<AuthSession> request) async {
    final s = await request;
    // Si entra un usuario distinto al último que usó el dispositivo, se purga
    // la base local para que sus datos nunca se mezclen con los del anterior.
    final lastUserId = await tokens.readLastUserId();
    if (lastUserId != null && lastUserId != s.userId) {
      await local.clearAll();
    }
    await tokens.saveSession(s);
    session.value = s;
  }

  /// El servidor rechazó el token (expirado). Se conservan los datos locales
  /// y los cambios pendientes; al volver a iniciar sesión se sincronizan.
  Future<void> expire() async {
    await tokens.clearToken();
    session.value = null;
  }

  /// Limpieza de sesión: purga SQLite y el almacenamiento seguro.
  Future<void> logout() async {
    await local.clearAll();
    await tokens.clearAll();
    session.value = null;
  }
}
