import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../models/task.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException(${statusCode ?? '-'}): $message';
}

/// 401: token ausente, inválido o expirado.
class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message) : super(statusCode: 401);
}

/// Sin red, DNS o servidor caído: el cambio sigue seguro en SQLite.
class NetworkException extends ApiException {
  NetworkException(super.message);
}

class AuthSession {
  const AuthSession({required this.token, required this.userId, required this.username});
  final String token;
  final String userId;
  final String username;
}

/// Resultado por registro del PUSH.
class PushResult {
  const PushResult({required this.id, required this.status, required this.conflict, this.task});

  factory PushResult.fromJson(Map<String, dynamic> json) => PushResult(
        id: json['id'] as String,
        status: json['status'] as String,
        conflict: json['conflict'] as bool? ?? false,
        task: json['task'] == null ? null : Task.fromRemoteJson(json['task'] as Map<String, dynamic>),
      );

  final String id;

  /// applied | duplicate | rejected | forbidden
  final String status;
  final bool conflict;
  final Task? task;
}

/// Página del PULL incremental.
class PullPage {
  const PullPage({required this.tasks, required this.cursor, required this.hasMore});
  final List<Task> tasks;
  final int cursor;
  final bool hasMore;
}

/// Contrato remoto que usa el motor de sync (permite usar un fake en pruebas).
abstract interface class TaskRemoteApi {
  Future<List<PushResult>> pushTasks(List<Task> tasks);
  Future<PullPage> fetchChanges({required int since});
}

class ApiClient implements TaskRemoteApi {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  })  : _baseUrl = normalizeBaseUrl(baseUrl ?? AppConfig.apiBaseUrl),
        _client = client ?? http.Client(),
        _tokenProvider = tokenProvider;

  String _baseUrl;
  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;

  String get baseUrl => _baseUrl;
  set baseUrl(String value) => _baseUrl = normalizeBaseUrl(value);

  /// `10.10.62.19:3000/` -> `http://10.10.62.19:3000`
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  // ------------------------------------------------------------------ Auth
  Future<AuthSession> login(String username, String password) =>
      _auth('/auth/login', username, password);

  Future<AuthSession> register(String username, String password) =>
      _auth('/auth/register', username, password);

  Future<AuthSession> _auth(String path, String username, String password) async {
    final json = await _send('POST', path, body: {'username': username, 'password': password}, auth: false);
    final user = json['user'] as Map<String, dynamic>;
    return AuthSession(
      token: json['token'] as String,
      userId: user['id'] as String,
      username: user['username'] as String,
    );
  }

  // ----------------------------------------------------------------- Tasks
  @override
  Future<List<PushResult>> pushTasks(List<Task> tasks) async {
    final json = await _send('POST', '/tasks/sync', body: {
      'tasks': tasks.map((t) => t.toRemoteJson()).toList(),
    });
    return (json['results'] as List<dynamic>)
        .map((e) => PushResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PullPage> fetchChanges({required int since}) async {
    final json = await _send('GET', '/tasks/changes?since=$since');
    return PullPage(
      tasks: (json['tasks'] as List<dynamic>)
          .map((e) => Task.fromRemoteJson(e as Map<String, dynamic>))
          .toList(),
      cursor: (json['cursor'] as num).toInt(),
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  // ------------------------------------------------------------------ HTTP
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final token = await _tokenProvider?.call();
      if (token == null) throw UnauthorizedException('Sin sesión activa');
      headers['Authorization'] = 'Bearer $token';
    }

    final request = http.Request(method, Uri.parse('$_baseUrl$path'))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(AppConfig.httpTimeout);
      response = await http.Response.fromStream(streamed).timeout(AppConfig.httpTimeout);
    } on SocketException catch (e) {
      throw NetworkException('Sin conexión con el servidor (${e.message})');
    } on TimeoutException {
      throw NetworkException('Tiempo de espera agotado');
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    }

    Map<String, dynamic> json;
    try {
      json = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException('Respuesta no válida del servidor', statusCode: response.statusCode);
    }

    if (response.statusCode == 401) {
      throw UnauthorizedException(json['error'] as String? ?? 'No autorizado');
    }
    if (response.statusCode >= 400) {
      throw ApiException(json['error'] as String? ?? 'Error HTTP', statusCode: response.statusCode);
    }
    return json;
  }

  void close() => _client.close();
}
