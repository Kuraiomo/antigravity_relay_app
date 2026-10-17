// Chat message models for the Antigravity conversation UI.

import 'token_usage.dart';

enum MessageSender {
  user,
  assistant,
  system,
}

enum MessageKind {
  userPrompt,
  assistantResponse,
  statusUpdate,
  error,
  permissionRequest,
}

class ChatMessage {
  final String id;
  final String requestId;
  final String taskId;
  final MessageSender sender;
  final MessageKind kind;
  final String content;
  final String? conversationId;
  final String? workspaceId;
  final DateTime timestamp;
  final bool isStreaming;
  final bool isCompleted;
  final bool isFailed;
  final Map<String, dynamic>? metadata;
  final TokenUsage? tokenUsage;

  const ChatMessage({
    required this.id,
    required this.requestId,
    this.taskId = '',
    required this.sender,
    required this.kind,
    required this.content,
    this.conversationId,
    this.workspaceId,
    required this.timestamp,
    this.isStreaming = false,
    this.isCompleted = false,
    this.isFailed = false,
    this.metadata,
    this.tokenUsage,
  });

  ChatMessage copyWith({
    String? content,
    String? conversationId,
    String? workspaceId,
    bool? isStreaming,
    bool? isCompleted,
    bool? isFailed,
    Map<String, dynamic>? metadata,
    MessageKind? kind,
    TokenUsage? tokenUsage,
  }) {
    return ChatMessage(
      id: id,
      requestId: requestId,
      taskId: taskId,
      sender: sender,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      conversationId: conversationId ?? this.conversationId,
      workspaceId: workspaceId ?? this.workspaceId,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      isCompleted: isCompleted ?? this.isCompleted,
      isFailed: isFailed ?? this.isFailed,
      metadata: metadata ?? this.metadata,
      tokenUsage: tokenUsage ?? this.tokenUsage,
    );
  }
}
