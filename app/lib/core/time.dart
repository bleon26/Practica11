/// Utilidades de tiempo para la resolución de colisiones (Last-Write-Wins).
library;

/// Marca temporal ISO-8601 en UTC con microsegundos, p. ej.
/// `2026-11-19T22:10:11.123456Z`.
String nowIsoUtc() => DateTime.now().toUtc().toIso8601String();

/// Compara dos marcas ISO-8601. <0 si [a] es anterior, 0 si iguales, >0 si posterior.
int compareIso(String a, String b) => DateTime.parse(a).compareTo(DateTime.parse(b));

/// Devuelve una marca estrictamente posterior a [previous].
///
/// Si el reloj del dispositivo está atrasado respecto a la última versión
/// conocida del registro, una edición nueva "parecería vieja" y perdería el
/// LWW. Se garantiza monotonía sumando 1 ms a la versión previa.
String nextIsoAfter(String? previous) {
  final now = DateTime.now().toUtc();
  if (previous == null) return now.toIso8601String();
  final prev = DateTime.parse(previous).toUtc();
  return (now.isAfter(prev) ? now : prev.add(const Duration(milliseconds: 1))).toIso8601String();
}
