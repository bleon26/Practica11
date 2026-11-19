import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_tasks/data/models/task.dart';

void main() {
  final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('Task.create genera UUID v4 offline, UTC y bandera sucia', () {
    final t = Task.create(title: '  Revisar inventario ');
    expect(uuidV4.hasMatch(t.id), isTrue);
    expect(t.title, 'Revisar inventario');
    expect(t.updatedAt.endsWith('Z'), isTrue);
    expect(t.isSynced, isFalse);
    expect(t.version, 0);
  });

  test('edit() avanza updated_at aunque el reloj local esté atrasado', () {
    final future = DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
    final t = Task(id: 'id', title: 'a', updatedAt: future, isSynced: true, version: 3);
    final e = t.edit(title: 'b');
    expect(DateTime.parse(e.updatedAt).isAfter(DateTime.parse(future)), isTrue);
    expect(e.isSynced, isFalse);
    expect(e.version, 3, reason: 'version = última versión de servidor conocida (base_version)');
  });

  test('toMap/fromMap conserva todos los metadatos de sync', () {
    final t = Task.create(title: 'x').markDeleted();
    final back = Task.fromMap(t.toMap());
    expect(back, t);
    expect(t.toMap(isSynced: 0)['is_synced'], 0);
    expect(t.toMap()['is_deleted'], 1);
  });

  test('toRemoteJson envía base_version null si nunca se sincronizó', () {
    final t = Task.create(title: 'x');
    expect(t.toRemoteJson()['base_version'], isNull);
    expect(t.copyWith(version: 2).toRemoteJson()['base_version'], 2);
  });

  test('fromRemoteJson marca el registro como sincronizado', () {
    final t = Task.fromRemoteJson({
      'id': 'id',
      'title': 't',
      'description': '',
      'is_done': 1,
      'is_deleted': 0,
      'updated_at': '2026-11-19T10:00:00.000Z',
      'version': 4,
    });
    expect(t.isSynced, isTrue);
    expect(t.isDone, isTrue);
    expect(t.version, 4);
  });
}
