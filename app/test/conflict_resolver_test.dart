import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_tasks/data/models/task.dart';
import 'package:offline_first_tasks/sync/conflict_resolver.dart';

Task _t({required String at, bool synced = false, String title = 'x'}) =>
    Task(id: 'a2b5b8f0-0000-4000-8000-000000000001', title: title, updatedAt: at, isSynced: synced);

void main() {
  const older = '2026-11-19T10:00:00.000Z';
  const newer = '2026-11-19T10:05:00.000Z';

  test('registro inexistente localmente se inserta', () {
    expect(ConflictResolver.resolve(local: null, remote: _t(at: newer, synced: true)), MergeDecision.insertRemote);
  });

  test('sin cambios pendientes, la nube siempre gana', () {
    expect(
      ConflictResolver.resolve(local: _t(at: newer, synced: true), remote: _t(at: older, synced: true)),
      MergeDecision.overwriteWithRemote,
    );
  });

  test('LWW: cambio local pendiente MÁS reciente se conserva', () {
    expect(ConflictResolver.resolve(local: _t(at: newer), remote: _t(at: older, synced: true)), MergeDecision.keepLocal);
  });

  test('LWW: cambio remoto más reciente pisa el local pendiente', () {
    expect(
      ConflictResolver.resolve(local: _t(at: older), remote: _t(at: newer, synced: true)),
      MergeDecision.overwriteWithRemote,
    );
  });

  test('empate de updated_at (ACK perdido) se resuelve tomando la nube', () {
    expect(
      ConflictResolver.resolve(local: _t(at: older), remote: _t(at: older, synced: true)),
      MergeDecision.overwriteWithRemote,
    );
  });

  test('compara con precisión de microsegundos', () {
    expect(
      ConflictResolver.resolve(
        local: _t(at: '2026-11-19T10:00:00.000002Z'),
        remote: _t(at: '2026-11-19T10:00:00.000001Z', synced: true),
      ),
      MergeDecision.keepLocal,
    );
  });
}
