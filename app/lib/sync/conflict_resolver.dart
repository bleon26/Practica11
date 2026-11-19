import '../core/time.dart';
import '../data/models/task.dart';

/// Resultado de comparar un registro local contra uno remoto (fase MERGE).
enum MergeDecision {
  /// No existe localmente: se inserta tal cual llega de la nube.
  insertRemote,

  /// La nube gana: se sobrescribe la copia local y queda `is_synced = 1`.
  overwriteWithRemote,

  /// La copia local tiene cambios pendientes MÁS recientes: se conserva y
  /// se subirá en el próximo PUSH.
  keepLocal,
}

/// Estrategia Last-Write-Wins por `updated_at` (UTC).
///
/// El servidor complementa con control de versiones (`version`/`base_version`)
/// para *detectar* y registrar ediciones concurrentes.
class ConflictResolver {
  const ConflictResolver._();

  static MergeDecision resolve({required Task? local, required Task remote}) {
    if (local == null) return MergeDecision.insertRemote;

    // Sin cambios locales pendientes: la nube es la referencia.
    if (local.isSynced) return MergeDecision.overwriteWithRemote;

    // Hay una edición local pendiente: gana la escritura más reciente.
    // En empate (mismo updated_at) es el mismo cambio ya confirmado por la
    // nube (ACK perdido): se toma la copia remota y queda sincronizada.
    return compareIso(local.updatedAt, remote.updatedAt) > 0
        ? MergeDecision.keepLocal
        : MergeDecision.overwriteWithRemote;
  }
}
