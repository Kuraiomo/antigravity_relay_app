import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'relay_service.dart';
import '../models/chat_message.dart';
import '../models/task_model.dart';
import '../models/event_model.dart';
import '../models/token_usage.dart';

/// Manages task submission, chat message tracking, and live streaming.
class TaskService extends ChangeNotifier {
  static const _uuid = Uuid();

  AuthService? _auth;
  RelayService? _relay;
  StreamSubscription<EventModel>? _eventSubscription;

  final List<TaskModel> _tasks = [];
  TaskModel? _activeTask;
  bool _isSubmitting = false;
  String? _error;

  // ── Chat & Conversation state ──────────────────────────
  final List<ChatMessage> _messages = [];
  int _currentMessageIndex = 0;
  String? _activeConversationId;
  String? _activeWorkspaceId;
  String _permissionMode = 'request-review';
  String? _effectivePermissionMode;

  // ── Getters ───────────────────────────────────────────

  List<TaskModel> get tasks => List.unmodifiable(_tasks);
  TaskModel? get activeTask => _activeTask;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  int get currentMessageIndex => _currentMessageIndex;
  int get totalMessages => _messages.length;

  ChatMessage? get currentMessage =>
      _messages.isNotEmpty && _currentMessageIndex >= 0 && _currentMessageIndex < _messages.length
          ? _messages[_currentMessageIndex]
          : null;

  String get positionIndicatorText =>
      _messages.isEmpty ? '0 of 0' : '${_currentMessageIndex + 1} of ${_messages.length}';

  bool get canGoPrevious => _currentMessageIndex > 0;
  bool get canGoNext => _currentMessageIndex < _messages.length - 1;

  String? get activeConversationId => _activeConversationId;
  String? get activeWorkspaceId => _activeWorkspaceId;
  String get permissionMode => _permissionMode;
  String? get effectivePermissionMode => _effectivePermissionMode;

  /// True if the CLI applied an effective mode different from what was requested.
  bool get isPermissionModeMismatch {
    if (_effectivePermissionMode == null) return false;
    final eff = _effectivePermissionMode!.toLowerCase().trim();
    final req = _permissionMode.toLowerCase().trim();
    if (req == 'full-auto' || req == 'auto') {
      return eff != 'always-proceed' && eff != 'full-auto' && eff != 'auto';
    }
    if (req == 'accept-edits' || req == 'edit') {
      return eff != 'accept-edits' && eff != 'edit';
    }
    if (req == 'request-review' || req == 'review') {
      return eff != 'request-review' && eff != 'review';
    }
    return false;
  }

  /// Cumulative token usage across all assistant responses in the current session.
  TokenUsage get conversationTokenUsage {
    var total = const TokenUsage();
    for (final m in _messages) {
      if (m.sender == MessageSender.assistant && m.tokenUsage != null) {
        total += m.tokenUsage!;
      }
    }
    return total;
  }

  void setPermissionMode(String mode) {
    _permissionMode = mode;
    _effectivePermissionMode = null;
    notifyListeners();
  }

  // ── Dependency update ─────────────────────────────────

  void updateDependencies(AuthService auth, RelayService relay) {
    _auth = auth;

    if (_relay != relay) {
      _eventSubscription?.cancel();
      _relay = relay;
      _eventSubscription = relay.eventStream.listen(_onEvent);
    }
  }

  // ── Navigation methods ────────────────────────────────

  void previousMessage() {
    if (canGoPrevious) {
      _currentMessageIndex--;
      notifyListeners();
    }
  }

  void nextMessage() {
    if (canGoNext) {
      _currentMessageIndex++;
      notifyListeners();
    }
  }

  void selectMessage(int index) {
    if (index >= 0 && index < _messages.length) {
      _currentMessageIndex = index;
      notifyListeners();
    }
  }

  void jumpToLatest() {
    if (_messages.isNotEmpty) {
      _currentMessageIndex = _messages.length - 1;
      notifyListeners();
    }
  }

  void startNewConversation() {
    _activeConversationId = null;
    _effectivePermissionMode = null;
    notifyListeners();
  }

  void clearConversation() {
    _messages.clear();
    _currentMessageIndex = 0;
    _activeConversationId = null;
    notifyListeners();
  }

  // ── Submit task ───────────────────────────────────────

  /// Submit a new task to the relay.
  Future<TaskModel?> submitTask({
    required String operation,
    required String deviceId,
    required String workspaceId,
    required Map<String, dynamic> payload,
  }) async {
    if (_auth == null || !_auth!.isAuthenticated) {
      _error = 'Authentication required';
      notifyListeners();
      return null;
    }

    if (_relay == null || !_relay!.isConnected) {
      _error = 'Not connected to relay';
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final requestId = _uuid.v4();
      final taskId = 'task-${DateTime.now().millisecondsSinceEpoch}';
      final task = TaskModel(
        requestId: requestId,
        taskId: taskId,
        operation: operation,
        workspaceId: workspaceId,
        prompt: payload['prompt'] as String? ?? '',
        status: TaskStatus.pending,
        createdAt: DateTime.now(),
      );

      _tasks.insert(0, task);
      _activeTask = task;
      _activeWorkspaceId = workspaceId;

      // ── Create ChatMessages for prompt or command ────
      if (operation == 'antigravity.prompt') {
        final promptText = payload['prompt'] as String? ?? '';
        final userMsg = ChatMessage(
          id: 'user-$requestId',
          requestId: requestId,
          taskId: taskId,
          sender: MessageSender.user,
          kind: MessageKind.userPrompt,
          content: promptText,
          conversationId: _activeConversationId,
          workspaceId: workspaceId,
          timestamp: DateTime.now(),
          isCompleted: true,
        );
        _messages.add(userMsg);

        final asstMsg = ChatMessage(
          id: 'asst-$requestId',
          requestId: requestId,
          taskId: taskId,
          sender: MessageSender.assistant,
          kind: MessageKind.assistantResponse,
          content: '',
          conversationId: _activeConversationId,
          workspaceId: workspaceId,
          timestamp: DateTime.now(),
          isStreaming: true,
        );
        _messages.add(asstMsg);

        // Automatically select the newest assistant response
        _currentMessageIndex = _messages.length - 1;
      } else if (operation == 'terminal.execute') {
        final cmd = payload['command'] as String? ?? '';
        final userMsg = ChatMessage(
          id: 'cmd-$requestId',
          requestId: requestId,
          taskId: taskId,
          sender: MessageSender.user,
          kind: MessageKind.userPrompt,
          content: '> $cmd',
          workspaceId: workspaceId,
          timestamp: DateTime.now(),
          isCompleted: true,
        );
        _messages.add(userMsg);

        final sysMsg = ChatMessage(
          id: 'term-$requestId',
          requestId: requestId,
          taskId: taskId,
          sender: MessageSender.system,
          kind: MessageKind.statusUpdate,
          content: 'Running command on device...',
          workspaceId: workspaceId,
          timestamp: DateTime.now(),
          isStreaming: true,
        );
        _messages.add(sysMsg);
        _currentMessageIndex = _messages.length - 1;
      }

      // Attach existing conversation ID for follow-up prompts
      final effectivePayload = Map<String, dynamic>.from(payload);
      if (_activeConversationId != null && !effectivePayload.containsKey('conversation_id')) {
        effectivePayload['conversation_id'] = _activeConversationId;
      }

      // Send to relay
      _relay!.send({
        'type': 'task.submit',
        'request_id': requestId,
        'task_id': taskId,
        'operation': operation,
        'workspace_id': workspaceId,
        'device_id': deviceId,
        'payload': effectivePayload,
      });

      notifyListeners();
      return task;
    } catch (e) {
      _error = 'Failed to submit task: $e';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Convenience: submit a prompt task.
  Future<TaskModel?> submitPrompt({
    required String prompt,
    required String deviceId,
    required String workspaceId,
    String? permissionMode,
  }) {
    return submitTask(
      operation: 'antigravity.prompt',
      deviceId: deviceId,
      workspaceId: workspaceId,
      payload: {
        'prompt': prompt,
        'permission_mode': permissionMode ?? _permissionMode,
      },
    );
  }

  /// Convenience: submit a terminal command (requires prior confirmation).
  Future<TaskModel?> submitCommand({
    required String command,
    required String deviceId,
    required String workspaceId,
  }) {
    return submitTask(
      operation: 'terminal.execute',
      deviceId: deviceId,
      workspaceId: workspaceId,
      payload: {'command': command},
    );
  }

  // ── Event handling ────────────────────────────────────

  void _onEvent(EventModel event) {
    if (event.type != 'task.event') return;

    // 1. Update task model for backwards compatibility
    final taskIdx = _tasks.indexWhere((t) => t.requestId == event.requestId);
    if (taskIdx >= 0) {
      final task = _tasks[taskIdx];
      final newEvent = TaskEvent(
        event: event.event,
        message: event.message,
        data: event.payload,
        timestamp: event.timestamp,
      );

      TaskStatus newStatus = task.status;
      DateTime? completedAt = task.completedAt;

      switch (event.event) {
        case 'accepted':
          newStatus = TaskStatus.accepted;
        case 'running':
          newStatus = TaskStatus.running;
        case 'completed':
          newStatus = TaskStatus.completed;
          completedAt = DateTime.now();
        case 'failed':
          newStatus = TaskStatus.failed;
          completedAt = DateTime.now();
      }

      _tasks[taskIdx] = task.copyWith(
        status: newStatus,
        events: [...task.events, newEvent],
        completedAt: completedAt,
      );

      if (_activeTask?.requestId == task.requestId) {
        _activeTask = _tasks[taskIdx];
      }
    }

    // 2. Update conversation ChatMessages
    final msgIdx = _messages.indexWhere(
      (m) => m.requestId == event.requestId && (m.sender == MessageSender.assistant || m.sender == MessageSender.system),
    );

    final convId = event.payload?['conversation_id'] as String?;
    if (convId != null && convId.isNotEmpty) {
      _activeConversationId = convId;
    }

    final effPerm = event.payload?['effective_permission_mode'] as String?;
    if (effPerm != null && effPerm.isNotEmpty) {
      _effectivePermissionMode = effPerm;
    }

    TokenUsage? parsedUsage;
    final rawUsage = event.payload?['usage'];
    if (rawUsage is Map<String, dynamic>) {
      parsedUsage = TokenUsage.fromJson(rawUsage);
    }

    if (msgIdx >= 0) {
      final currentMsg = _messages[msgIdx];

      switch (event.event) {
        case 'stdout':
          final updatedContent = currentMsg.content + event.message;
          _messages[msgIdx] = currentMsg.copyWith(
            content: updatedContent,
            conversationId: convId ?? currentMsg.conversationId,
            tokenUsage: parsedUsage ?? currentMsg.tokenUsage,
            isStreaming: true,
          );
          // Keep current view on the latest message if user was already at or near latest
          if (_currentMessageIndex >= _messages.length - 2) {
            _currentMessageIndex = _messages.length - 1;
          }

        case 'usage':
          if (parsedUsage != null) {
            _messages[msgIdx] = currentMsg.copyWith(
              tokenUsage: parsedUsage,
            );
          }

        case 'completed':
          String finalContent = currentMsg.content;
          // Only use completed response text if nothing was streamed yet
          if (finalContent.isEmpty) {
            finalContent = event.payload?['response'] as String? ?? event.message;
          }
          _messages[msgIdx] = currentMsg.copyWith(
            content: finalContent,
            conversationId: convId ?? currentMsg.conversationId,
            tokenUsage: parsedUsage ?? currentMsg.tokenUsage,
            isStreaming: false,
            isCompleted: true,
          );

        case 'failed':
          final errText = currentMsg.content.isEmpty
              ? (event.message.isNotEmpty ? event.message : 'Task failed')
              : '${currentMsg.content}\n\n[Error: ${event.message}]';
          _messages[msgIdx] = currentMsg.copyWith(
            content: errText,
            conversationId: convId ?? currentMsg.conversationId,
            tokenUsage: parsedUsage ?? currentMsg.tokenUsage,
            isStreaming: false,
            isFailed: true,
            kind: MessageKind.error,
          );

        case 'permission_request':
          _messages[msgIdx] = currentMsg.copyWith(
            kind: MessageKind.permissionRequest,
            metadata: event.payload,
          );
      }
    }

    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────

  void setActiveTask(TaskModel task) {
    _activeTask = task;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

