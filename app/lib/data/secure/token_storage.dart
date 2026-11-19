import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../remote/api_client.dart';

/// Cifrado en reposo del token de sesión.
///
/// `flutter_secure_storage` cifra los valores con una clave protegida por el
/// **Android Keystore** (AES-GCM) o el **Keychain** de iOS. El token JWT nunca
/// se guarda en SQLite ni en SharedPreferences en texto plano.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kToken = 'auth_token';
  static const _kUserId = 'auth_user_id';
  static const _kUsername = 'auth_username';

  /// UID del último usuario que usó este dispositivo. Se conserva aunque el
  /// token expire para decidir si la base local pertenece al mismo usuario.
  static const _kLastUserId = 'last_user_id';

  Future<void> saveSession(AuthSession s) async {
    await _storage.write(key: _kToken, value: s.token);
    await _storage.write(key: _kUserId, value: s.userId);
    await _storage.write(key: _kUsername, value: s.username);
    await _storage.write(key: _kLastUserId, value: s.userId);
  }

  Future<AuthSession?> readSession() async {
    final token = await _storage.read(key: _kToken);
    final userId = await _storage.read(key: _kUserId);
    final username = await _storage.read(key: _kUsername);
    if (token == null || userId == null || username == null) return null;
    return AuthSession(token: token, userId: userId, username: username);
  }

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<String?> readLastUserId() => _storage.read(key: _kLastUserId);

  /// Token expirado: se borra el token pero se recuerda el UID para no
  /// perder cambios offline pendientes si vuelve a entrar el mismo usuario.
  Future<void> clearToken() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kUsername);
  }

  /// Cierre de sesión explícito: borra todo.
  Future<void> clearAll() => _storage.deleteAll();
}
