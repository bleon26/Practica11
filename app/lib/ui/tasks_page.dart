import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/task.dart';
import '../data/remote/api_client.dart';
import '../sync/sync_repository.dart';
import 'widgets/offline_banner.dart';
import 'widgets/task_editor_dialog.dart';

/// Pantalla principal. Escucha ÚNICAMENTE Streams de SQLite: nunca espera a
/// la red para mostrar o guardar datos.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.services, required this.session});

  final AppServices services;
  final AuthSession session;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  late final Stream<List<Task>> _tasks = widget.services.tasks.watchTasks();
  late final Stream<int> _pending = widget.services.tasks.watchPendingCount();

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_s.onResumed());
  }

  Future<void> _create() async {
    final draft = await showTaskEditor(context);
    if (draft == null) return;
    await _s.tasks.create(title: draft.title, description: draft.description);
  }

  Future<void> _edit(Task task) async {
    final draft = await showTaskEditor(context, task: task);
    if (draft == null) return;
    await _s.tasks.update(task, title: draft.title, description: draft.description);
  }

  Future<void> _delete(Task task) async {
    final deleted = await _s.tasks.delete(task);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('"${task.title}" eliminada'),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => _s.tasks.restore(deleted)),
      ));
  }

  Future<void> _manualSync() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_s.connectivity.online.value) {
      messenger.showSnackBar(const SnackBar(content: Text('Sin conexión: los cambios siguen guardados localmente.')));
      return;
    }
    await _s.syncNow();
    final st = _s.sync.status.value;
    messenger.showSnackBar(SnackBar(
      content: Text(st.phase == SyncPhase.error ? 'Error al sincronizar: ${st.message}' : 'Sincronizado con la nube'),
    ));
  }

  Future<void> _logout() async {
    final pending = await _s.local.countPending();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: Text(pending == 0
            ? 'Se borrarán los datos locales de este dispositivo.'
            : 'Tienes $pending cambios SIN sincronizar que se perderán. '
                'Conéctate y sincroniza antes de salir si quieres conservarlos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true) await _s.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis tareas'),
            Text(widget.session.username, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        actions: [
          _SyncIndicator(services: _s),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'sync' ? _manualSync() : _logout(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sync', child: ListTile(leading: Icon(Icons.sync), title: Text('Sincronizar ahora'))),
              PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Cerrar sesión'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _s.connectivity.online,
            builder: (_, online, _) => StreamBuilder<int>(
              stream: _pending,
              builder: (_, snap) => OfflineBanner(online: online, pending: snap.data ?? 0),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _manualSync,
              child: StreamBuilder<List<Task>>(
                stream: _tasks,
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('Error local: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final tasks = snap.data!;
                  if (tasks.isEmpty) return const _EmptyState();
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _TaskTile(
                      task: tasks[i],
                      onToggle: () => _s.tasks.toggleDone(tasks[i]),
                      onEdit: () => _edit(tasks[i]),
                      onDelete: () => _delete(tasks[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onToggle, required this.onEdit, required this.onDelete});

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final edited = DateTime.parse(task.updatedAt).toLocal();
    final time = TimeOfDay.fromDateTime(edited).format(context);
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onEdit,
        leading: Checkbox(value: task.isDone, onChanged: (_) => onToggle()),
        title: Text(
          task.title,
          style: task.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Text(
          [if (task.description.isNotEmpty) task.description, 'Editada $time · v${task.version}'].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: task.description.isNotEmpty,
        trailing: Tooltip(
          message: task.isSynced ? 'Sincronizada (is_synced = 1)' : 'Pendiente de subir (is_synced = 0)',
          child: Icon(
            task.isSynced ? Icons.cloud_done : Icons.cloud_upload_outlined,
            color: task.isSynced ? Colors.teal : Colors.orange,
          ),
        ),
      ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: services.connectivity.online,
      builder: (_, online, _) => ValueListenableBuilder<SyncStatus>(
        valueListenable: services.sync.status,
        builder: (_, st, _) {
          if (!online) {
            return const Tooltip(message: 'Offline', child: Padding(
              padding: EdgeInsets.all(12), child: Icon(Icons.cloud_off)));
          }
          return switch (st.phase) {
            SyncPhase.syncing => const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            SyncPhase.error => Tooltip(
                message: 'Error: ${st.message}',
                child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.sync_problem, color: Colors.red)),
              ),
            SyncPhase.idle => Tooltip(
                message: st.lastSyncAt == null ? 'En línea' : 'Última sync ${TimeOfDay.fromDateTime(st.lastSyncAt!).format(context)}',
                child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.cloud_done_outlined)),
              ),
          };
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 64),
        SizedBox(height: 12),
        Center(child: Text('Sin tareas. Crea una — funciona incluso en modo avión.')),
      ],
    );
  }
}
