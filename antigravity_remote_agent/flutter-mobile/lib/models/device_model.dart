/// Represents an enrolled desktop agent device.
class DeviceModel {
  final String id;
  final String name;
  final String agentVersion;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isMockMode;

  const DeviceModel({
    required this.id,
    required this.name,
    this.agentVersion = '0.1.0',
    this.isOnline = false,
    this.lastSeen,
    this.isMockMode = false,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Device',
      agentVersion: json['agent_version'] as String? ?? '0.1.0',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String)
          : null,
      isMockMode: json['mock_mode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'agent_version': agentVersion,
        'is_online': isOnline,
        'last_seen': lastSeen?.toIso8601String(),
        'mock_mode': isMockMode,
      };

  DeviceModel copyWith({
    String? id,
    String? name,
    String? agentVersion,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isMockMode,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      agentVersion: agentVersion ?? this.agentVersion,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isMockMode: isMockMode ?? this.isMockMode,
    );
  }
}
