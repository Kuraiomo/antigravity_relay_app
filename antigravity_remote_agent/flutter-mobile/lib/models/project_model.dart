/// Represents a project / workspace available on a device.
class ProjectModel {
  final String id;
  final String name;
  final String path;
  final String deviceId;

  const ProjectModel({
    required this.id,
    required this.name,
    required this.path,
    required this.deviceId,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Project',
      path: json['path'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'device_id': deviceId,
      };
}
