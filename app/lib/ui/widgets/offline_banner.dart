import 'package:flutter/material.dart';

/// Indicador visual del estado offline (Paso 4) con el número de cambios
/// que esperan subir a la nube.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.online, required this.pending});

  final bool online;
  final int pending;

  @override
  Widget build(BuildContext context) {
    if (online) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final pendingText = pending == 0
        ? 'Tus cambios se guardan en el dispositivo.'
        : '$pending ${pending == 1 ? 'cambio pendiente' : 'cambios pendientes'} de sincronizar.';
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sin conexión · $pendingText Se subirán al reconectar.',
                key: const Key('offline-banner-text'),
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
