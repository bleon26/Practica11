import 'package:uuid/uuid.dart';

import '../../core/time.dart';

const _uuid = Uuid();

/// Entidad Tarea con metadatos de sincronización.
///
/// | Campo       | Uso                                                     |
/// |-------------|---------------------------------------------------------|
/// | id          | UUID v4 generado OFFLINE en el cliente (idempotencia)   |
/// | isSynced    | false = pendiente de subir (bandera sucia)              |
/// | updatedAt   | ISO-8601 UTC, criterio Last-Write-Wins                  |
/// | isDeleted   | Borrado lógico (soft delete) que se propaga a la nube   |
/// | version     | Última versión del servidor conocida (0 = nunca subida) |
class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.isDone = false,
    this.isSynced = false,
    required this.updatedAt,
    this.isDeleted = false,
    this.version = 0,
  });

  /// Crea una tarea nueva sin necesidad de red: el UUID se genera localmente.
  factory Task.create({required String title, String description = ''}) => Task(
        id: _uuid.v4(),
        title: title.trim(),
        description: description.trim(),
        updatedAt: nowIsoUtc(),
      );

  final String id;
  final String title;
  final String description;
  final bool isDone;
  final bool isSynced;
  final String updatedAt;
  final bool isDeleted;
  final int version;

  /// Aplica una edición local: nueva marca temporal y bandera sucia.
  Task edit({String? title, String? description, bool? isDone}) => copyWith(
        title: title?.trim(),
        description: description?.trim(),
        isDone: isDone,
        updatedAt: nextIsoAfter(updatedAt),
        isSynced: false,
      );

  /// Borrado lógico: el registro se conserva hasta que la nube lo confirma.
  Task markDeleted() => copyWith(isDeleted: true, updatedAt: nextIsoAfter(updatedAt), isSynced: false);

  /// Revierte un borrado lógico (botón "Deshacer").
  Task restore() => copyWith(isDeleted: false, updatedAt: nextIsoAfter(updatedAt), isSynced: false);

  Task copyWith({
    String? title,
    String? description,
    bool? isDone,
    bool? isSynced,
    String? updatedAt,
    bool? isDeleted,
    int? version,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        isDone: isDone ?? this.isDone,
        isSynced: isSynced ?? this.isSynced,
        updatedAt: updatedAt ?? this.updatedAt,
        isDeleted: isDeleted ?? this.isDeleted,
        version: version ?? this.version,
      );

  // ---------------------------------------------------------------- SQLite
  /// Mapa para la tabla `tasks`. [isSynced] permite forzar la bandera
  /// (p. ej. `t.toMap(isSynced: 0)` al guardar un cambio local).
  Map<String, Object?> toMap({int? isSynced}) => {
        'id': id,
        'title': title,
        'description': description,
        'is_done': isDone ? 1 : 0,
        'is_synced': isSynced ?? (this.isSynced ? 1 : 0),
        'updated_at': updatedAt,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
      };

  factory Task.fromMap(Map<String, Object?> map) => Task(
        id: map['id']! as String,
        title: map['title']! as String,
        description: (map['description'] as String?) ?? '',
        isDone: (map['is_done'] as int? ?? 0) == 1,
        isSynced: (map['is_synced'] as int? ?? 0) == 1,
        updatedAt: map['updated_at']! as String,
        isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
        version: map['version'] as int? ?? 0,
      );

  // ------------------------------------------------------------------- API
  /// Cuerpo enviado en el PUSH. `base_version` permite al servidor detectar
  /// ediciones concurrentes (control de versiones).
  Map<String, Object?> toRemoteJson() => {
        'id': id,
        'title': title,
        'description': description,
        'is_done': isDone ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'updated_at': updatedAt,
        'base_version': version == 0 ? null : version,
      };

  /// Registro recibido de la nube: ya está sincronizado por definición.
  factory Task.fromRemoteJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        isDone: (json['is_done'] as num? ?? 0) == 1,
        isDeleted: (json['is_deleted'] as num? ?? 0) == 1,
        updatedAt: json['updated_at'] as String,
        version: (json['version'] as num? ?? 0).toInt(),
        isSynced: true,
      );

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.isDone == isDone &&
      other.isSynced == isSynced &&
      other.updatedAt == updatedAt &&
      other.isDeleted == isDeleted &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id, title, description, isDone, isSynced, updatedAt, isDeleted, version);

  @override
  String toString() => 'Task($id, "$title", synced=$isSynced, deleted=$isDeleted, v$version, $updatedAt)';
}
