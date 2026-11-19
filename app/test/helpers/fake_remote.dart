import 'package:offline_first_tasks/core/time.dart';
import 'package:offline_first_tasks/data/models/task.dart';
import 'package:offline_first_tasks/data/remote/api_client.dart';

/// Backend en memoria con la MISMA semántica que backend/src/syncService.js:
/// idempotencia por UUID, LWW por updated_at, version++ y cursor por revisión.
class FakeRemote implements TaskRemoteApi {
  final Map<String, Task> store = {};
  final Map<String, int> _revs = {};
  int _rev = 0;
  bool offline = false;
  int pushCalls = 0;

  /// Simula un cambio hecho desde OTRO dispositivo directamente en la nube.
  Task serverWrite(Task t) {
    final existing = store[t.id];
    return _write(t.copyWith(version: (existing?.version ?? 0) + 1, isSynced: true));
  }

  Task _write(Task t) {
    _rev++;
    store[t.id] = t;
    _revs[t.id] = _rev;
    return t;
  }

  @override
  Future<List<PushResult>> pushTasks(List<Task> tasks) async {
    if (offline) throw NetworkException('modo avión');
    pushCalls++;
    return tasks.map((t) {
      final existing = store[t.id];
      if (existing == null) {
        final saved = _write(t.copyWith(version: 1, isSynced: true));
        return PushResult(id: t.id, status: 'applied', conflict: false, task: saved);
      }
      final cmp = compareIso(t.updatedAt, existing.updatedAt);
      if (cmp == 0) return PushResult(id: t.id, status: 'duplicate', conflict: false, task: existing);
      if (cmp > 0) {
        final saved = _write(t.copyWith(version: existing.version + 1, isSynced: true));
        return PushResult(id: t.id, status: 'applied', conflict: t.version < existing.version, task: saved);
      }
      return PushResult(id: t.id, status: 'rejected', conflict: true, task: existing);
    }).toList();
  }

  @override
  Future<PullPage> fetchChanges({required int since}) async {
    if (offline) throw NetworkException('modo avión');
    final changed = store.values.where((t) => _revs[t.id]! > since).toList()
      ..sort((a, b) => _revs[a.id]!.compareTo(_revs[b.id]!));
    return PullPage(
      tasks: changed,
      cursor: changed.isEmpty ? since : _revs[changed.last.id]!,
      hasMore: false,
    );
  }
}
