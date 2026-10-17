/// Represents a task submitted to a desktop agent.
enum TaskStatus {
  pending,
  accepted,
  running,
  completed,
  failed;

  bool get isTerminal => this == completed || this == failed;

  String get displayName {
    switch (this) {
      case pending:
        return 'Pending';
      case accepted:
        return 'Accepted';
      case running:
        return 'Running';
      case completed:
        return 'Completed';
      case failed:
        return 'Failed';
    }
  }
}

class TaskModel {
  final String requestId;
  final String taskId;
  final String operation;
  final String workspaceId;
  final String prompt;
  final TaskStatus status;
  final List<TaskEvent> events;
  final DateTime createdAt;
  final DateTime? completedAt;

  const TaskModel({
    required this.requestId,
    required this.taskId,
    required this.operation,
    this.workspaceId = '',
    this.prompt = '',
    this.status = TaskStatus.pending,
    this.events = const [],
    required this.createdAt,
    this.completedAt,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      requestId: json['request_id'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      operation: json['operation'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      status: TaskStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'pending'),
        orElse: () => TaskStatus.pending,
      ),
      events: (json['events'] as List<dynamic>?)
              ?.map((e) => TaskEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );
  }

  TaskModel copyWith({
    TaskStatus? status,
    List<TaskEvent>? events,
    DateTime? completedAt,
  }) {
    return TaskModel(
      requestId: requestId,
      taskId: taskId,
      operation: operation,
      workspaceId: workspaceId,
      prompt: prompt,
      status: status ?? this.status,
      events: events ?? this.events,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// A single status event for a task.
class TaskEvent {
  final String event;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  const TaskEvent({
    required this.event,
    this.message = '',
    this.data,
    required this.timestamp,
  });

  factory TaskEvent.fromJson(Map<String, dynamic> json) {
    return TaskEvent(
      event: json['event'] as String? ?? '',
      message: json['message'] as String? ??
          json['payload']?['message'] as String? ??
          '',
      data: json['data'] as Map<String, dynamic>? ??
          json['payload'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}
