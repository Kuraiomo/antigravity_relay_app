import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/models/chat_message.dart';
import 'package:antigravity_mobile/models/event_model.dart';
import 'package:antigravity_mobile/services/auth_service.dart';
import 'package:antigravity_mobile/services/device_service.dart';
import 'package:antigravity_mobile/services/relay_service.dart';
import 'package:antigravity_mobile/services/task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    dotenv.loadFromString(envString: '''
RELAY_URL=https://websocket.pagepal.in
RELAY_WS_URL=wss://websocket.pagepal.in/ws/desktop
DEVICE_ID=ayaan-windows-pc
DEVICE_NAME=Ayaan's Windows PC
USERNAME=ayaan
PASSWORD=antigravity-remote
DEFAULT_WORKSPACE_ID=C:\\Users\\ayaan\\OneDrive\\Desktop
DEFAULT_WORKSPACE_NAME=Antigravity Controller
MOCK_MODE=true
''');
  });

  Future<(AuthService, RelayService, TaskService)> createConnectedServices() async {
    final auth = AuthService();
    await auth.login(
      relayUrl: 'https://websocket.pagepal.in',
      username: 'ayaan',
      password: 'pwd',
      mockMode: true,
    );

    final relay = RelayService();
    relay.updateAuth(auth);
    // Allow mock connection to complete
    await Future.delayed(const Duration(milliseconds: 400));

    final taskService = TaskService();
    taskService.updateDependencies(auth, relay);

    return (auth, relay, taskService);
  }

  group('ChatMessage & Navigation Tests', () {
    test('submitPrompt creates user and assistant messages, auto-selecting latest', () async {
      final (_, relay, taskService) = await createConnectedServices();

      final task = await taskService.submitPrompt(
        prompt: 'First prompt',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop\Antigravity_controller',
      );

      expect(task, isNotNull);
      expect(taskService.totalMessages, 2);
      expect(taskService.messages[0].sender, MessageSender.user);
      expect(taskService.messages[0].content, 'First prompt');
      expect(taskService.messages[1].sender, MessageSender.assistant);
      expect(taskService.messages[1].isStreaming, isTrue);

      // Auto-selected latest message (assistant placeholder)
      expect(taskService.currentMessageIndex, 1);
      expect(taskService.positionIndicatorText, '2 of 2');
      expect(taskService.canGoPrevious, isTrue);
      expect(taskService.canGoNext, isFalse);

      await relay.disconnect();
    });

    test('Navigating with previousMessage and nextMessage enforces boundaries', () async {
      final (_, relay, taskService) = await createConnectedServices();

      await taskService.submitPrompt(
        prompt: 'Prompt A',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop',
      );

      expect(taskService.currentMessageIndex, 1);

      // Go previous to user prompt
      taskService.previousMessage();
      expect(taskService.currentMessageIndex, 0);
      expect(taskService.positionIndicatorText, '1 of 2');
      expect(taskService.canGoPrevious, isFalse);
      expect(taskService.canGoNext, isTrue);

      // Attempting previous when at boundary should not decrement
      taskService.previousMessage();
      expect(taskService.currentMessageIndex, 0);

      // Go next to assistant response
      taskService.nextMessage();
      expect(taskService.currentMessageIndex, 1);
      expect(taskService.positionIndicatorText, '2 of 2');
      expect(taskService.canGoNext, isFalse);

      // Attempting next when at boundary should not increment
      taskService.nextMessage();
      expect(taskService.currentMessageIndex, 1);

      await relay.disconnect();
    });

    test('Streaming multiple stdout text deltas concatenates into single assistant message without duplicating', () async {
      final (_, relay, taskService) = await createConnectedServices();

      final task = await taskService.submitPrompt(
        prompt: 'Count numbers',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop',
      );
      final reqId = task!.requestId;

      // Dispatch 3 streamed chunks
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'stdout',
        requestId: reqId,
        message: '1, 2, ',
        payload: {'conversation_id': 'conv-test-999'},
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'stdout',
        requestId: reqId,
        message: '3, 4, ',
        payload: {'conversation_id': 'conv-test-999'},
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'stdout',
        requestId: reqId,
        message: '5.',
        payload: {'conversation_id': 'conv-test-999'},
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      // Check concatenated message
      final assistantMsg = taskService.messages[1];
      expect(assistantMsg.content, '1, 2, 3, 4, 5.');
      expect(assistantMsg.isStreaming, isTrue);
      expect(assistantMsg.conversationId, 'conv-test-999');
      expect(taskService.activeConversationId, 'conv-test-999');

      // Dispatch completed event with duplicate response text - should preserve streamed content without doubling
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'completed',
        requestId: reqId,
        message: 'Task completed',
        payload: {
          'response': '1, 2, 3, 4, 5.',
          'conversation_id': 'conv-test-999',
        },
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      final completedMsg = taskService.messages[1];
      expect(completedMsg.content, '1, 2, 3, 4, 5.');
      expect(completedMsg.isStreaming, isFalse);
      expect(completedMsg.isCompleted, isTrue);
      expect(taskService.totalMessages, 2); // Still just 2 messages!

      await relay.disconnect();
    });

    test('Follow-up prompt preserves conversationId and workspace', () async {
      final (_, relay, taskService) = await createConnectedServices();

      final task1 = await taskService.submitPrompt(
        prompt: 'First prompt',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop\Antigravity_controller',
      );

      // Simulate receiving conversation_id
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'stdout',
        requestId: task1!.requestId,
        message: 'Understood.',
        payload: {'conversation_id': 'conv-session-100'},
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(taskService.activeConversationId, 'conv-session-100');

      // Submit follow-up prompt
      final task2 = await taskService.submitPrompt(
        prompt: 'Follow-up question',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop\Antigravity_controller',
      );

      expect(task2, isNotNull);
      expect(taskService.totalMessages, 4); // 2 from first prompt, 2 from second
      expect(taskService.messages[2].content, 'Follow-up question');
      expect(taskService.messages[2].conversationId, 'conv-session-100');
      expect(taskService.messages[3].conversationId, 'conv-session-100');
      expect(taskService.currentMessageIndex, 3); // Auto-jumped to latest

      // Reset conversation
      taskService.startNewConversation();
      expect(taskService.activeConversationId, isNull);

      await relay.disconnect();
    });

    test('Failed task marks assistant message with error kind and failed status', () async {
      final (_, relay, taskService) = await createConnectedServices();

      final task = await taskService.submitPrompt(
        prompt: 'Trigger failure',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop',
      );

      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'failed',
        requestId: task!.requestId,
        message: 'Workspace directory does not exist',
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      final failedMsg = taskService.messages[1];
      expect(failedMsg.isFailed, isTrue);
      expect(failedMsg.isStreaming, isFalse);
      expect(failedMsg.kind, MessageKind.error);
      expect(failedMsg.content, contains('Workspace directory does not exist'));

      await relay.disconnect();
    });

    test('DeviceService allows configuring and selecting custom Windows workspace', () async {
      final auth = AuthService();
      await auth.login(
        relayUrl: 'https://websocket.pagepal.in',
        username: 'ayaan',
        password: 'pwd',
        mockMode: true,
      );

      final deviceService = DeviceService();
      deviceService.updateAuth(auth);

      const customDir = r'C:\Users\ayaan\OneDrive\Desktop\Antigravity_controller';
      deviceService.setCustomWorkspace(customDir, name: 'Antigravity Controller');

      expect(deviceService.selectedProject, isNotNull);
      expect(deviceService.selectedProject!.id, customDir);
      expect(deviceService.selectedProject!.name, 'Antigravity Controller');
      expect(deviceService.hasSelection, isTrue);

      // Switching workspace to another path
      const anotherDir = r'D:\Projects\Backend';
      deviceService.setCustomWorkspace(anotherDir);
      expect(deviceService.selectedProject!.id, anotherDir);
      expect(deviceService.selectedProject!.name, 'Backend');
    });
  });
}
