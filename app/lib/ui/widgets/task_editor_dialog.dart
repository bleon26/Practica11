import 'package:flutter/material.dart';

import '../../data/models/task.dart';

class TaskDraft {
  const TaskDraft(this.title, this.description);
  final String title;
  final String description;
}

/// Diálogo para crear o editar una tarea. Devuelve null si se cancela.
Future<TaskDraft?> showTaskEditor(BuildContext context, {Task? task}) {
  return showDialog<TaskDraft>(
    context: context,
    builder: (_) => _TaskEditorDialog(task: task),
  );
}

class _TaskEditorDialog extends StatefulWidget {
  const _TaskEditorDialog({this.task});
  final Task? task;

  @override
  State<_TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<_TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.task?.description ?? '');

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(TaskDraft(_title.text.trim(), _desc.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'Nueva tarea' : 'Editar tarea'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Título'),
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').trim().isEmpty ? 'El título es obligatorio' : null,
            ),
            TextFormField(
              controller: _desc,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
