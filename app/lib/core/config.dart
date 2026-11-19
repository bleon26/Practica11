/// Configuración de la app inyectada en tiempo de compilación.
///
///   flutter run --dart-define=API_URL=http://10.0.2.2:3000   (emulador Android)
///   flutter run --dart-define=API_URL=http://localhost:3000  (dispositivo físico + `adb reverse tcp:3000 tcp:3000`)
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Tiempo máximo de espera de cada petición HTTP.
  static const Duration httpTimeout = Duration(seconds: 15);

  /// Retardo para agrupar varias escrituras locales en un solo ciclo de sync.
  static const Duration syncDebounce = Duration(milliseconds: 800);

  /// Tamaño máximo de lote en el PUSH.
  static const int pushBatchSize = 200;
}
