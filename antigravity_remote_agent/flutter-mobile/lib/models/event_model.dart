/// Represents a streamed event from the relay / agent.
class EventModel {
  final String type;
  final String requestId;
  final String taskId;
  final String event;
  final String message;
  final Map<String, dynamic>? payload;
  final DateTime timestamp;

  const EventModel({
    required this.type,
    this.requestId = '',
    this.taskId = '',
    this.event = '',
    this.message = '',
    this.payload,
    required this.timestamp,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      type: json['type'] as String? ?? 'unknown',
      requestId: json['request_id'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      event: json['event'] as String? ?? '',
      message: json['payload']?['message'] as String? ??
          json['message'] as String? ??
          '',
      payload: json['payload'] as Map<String, dynamic>?,
      timestamp: DateTime.now(),
    );
  }
}
