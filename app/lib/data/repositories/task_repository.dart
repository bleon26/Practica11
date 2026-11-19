import '../local/task_local_datasource.dart';
import '../models/task.dart';

/// API de dominio que usa la UI. Toda escritura va PRIMERO a SQLite y luego
/// se avisa al motor de sync ([onLocalChange]) sin bloquear la interfaz.
class TaskRepository {
  TaskRepository({required this.local, required this.onLocalChange});

  final TaskLocalDataSource local;
  final void Function() onLocalChange;

  Stream<List<Task>> watchTasks() => local.watchTasks();
  Stream<int> watchPendingCount() => local.watchPendingCount();

  Future<Task> create({required String title, String description = ''}) async {
    final task = Task.create(title: title, description: description);
    await _save(task);
    return task;
  }

  Future<Task> update(Task task, {String? title, String? description, bool? isDone}) async {
    final edited = task.edit(title: title, description: description, isDone: isDone);
    await _save(edited);
    return edited;
  }

  Future<Task> toggleDone(Task task) => update(task, isDone: !task.isDone);

  /// Soft delete: se marca y se sincroniza; la nube lo propaga a otros equipos.
  Future<Task> delete(Task task) async {
    final deleted = task.markDeleted();
    await _save(deleted);
    return deleted;
  }

  Future<void> restore(Task deleted) => _save(deleted.restore());

  Future<void> _save(Task task) async {
    await local.saveLocal(task); // latencia percibida ~0 ms
    onLocalChange();
  }
}
