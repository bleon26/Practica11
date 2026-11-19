import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/remote/api_client.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.services});

  final AppServices services;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  late final _server = TextEditingController(text: widget.services.api.baseUrl);
  bool _registerMode = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = widget.services.auth;
    try {
      await auth.setServerUrl(_server.text);
      if (_registerMode) {
        await auth.register(_user.text.trim(), _pass.text);
      } else {
        await auth.login(_user.text.trim(), _pass.text);
      }
      await widget.services.onSignedIn();
    } on NetworkException {
      _error = 'Sin conexión con el servidor. El primer inicio de sesión requiere red; '
          'después la app funciona offline.';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Error inesperado: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.cloud_sync_outlined, size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Offline-First Tasks',
                        textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    Text('SQLite local · sync bidireccional',
                        textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _user,
                      decoration: const InputDecoration(labelText: 'Usuario', border: OutlineInputBorder()),
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      validator: (v) => RegExp(r'^[a-zA-Z0-9_.-]{3,32}$').hasMatch(v?.trim() ?? '')
                          ? null
                          : '3-32 caracteres: letras, números, _ . -',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pass,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => (v ?? '').length >= 8 ? null : 'Mínimo 8 caracteres',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_registerMode ? 'Crear cuenta' : 'Iniciar sesión'),
                    ),
                    TextButton(
                      onPressed: _loading ? null : () => setState(() => _registerMode = !_registerMode),
                      child: Text(_registerMode ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Servidor (IP de la PC con el backend)',
                        helperText: 'Ej. http://10.10.62.19:3000 · misma red Wi-Fi',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final uri = Uri.tryParse(ApiClient.normalizeBaseUrl(v ?? ''));
                        return uri != null && uri.host.isNotEmpty ? null : 'URL inválida';
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
