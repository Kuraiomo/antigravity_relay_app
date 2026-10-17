import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/models/event_model.dart';
import 'package:antigravity_mobile/models/token_usage.dart';
import 'package:antigravity_mobile/services/auth_service.dart';
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
    await Future.delayed(const Duration(milliseconds: 400));

    final taskService = TaskService();
    taskService.updateDependencies(auth, relay);

    return (auth, relay, taskService);
  }

  group('TokenUsage Model Tests', () {
    test('TokenUsage.fromJson correctly parses official CLI usage schema', () {
      final json = {
        'input_tokens': 15684,
        'output_tokens': 57,
        'thinking_tokens': 45,
        'cache_read_tokens': 120,
        'total_tokens': 15741,
      };

      final usage = TokenUsage.fromJson(json);

      expect(usage.inputTokens, 15684);
      expect(usage.outputTokens, 57);
      expect(usage.thinkingTokens, 45);
      expect(usage.cacheReadTokens, 120);
      expect(usage.totalTokens, 15741);
      expect(usage.isEmpty, isFalse);
      expect(usage.formatCompact(), 'Input: 15,684 | Output: 57 | Total: 15,741 | Cached: 120');
      expect(usage.formatShort(), '15.7k tokens');
    });

    test('TokenUsage handles missing fields, zero values, and null gracefully', () {
      final nullUsage = TokenUsage.fromJson(null);
      expect(nullUsage.isEmpty, isTrue);
      expect(nullUsage.formatCompact(), 'Usage: N/A');
      expect(nullUsage.formatShort(), '0 tokens');

      final emptyUsage = TokenUsage.fromJson({});
      expect(emptyUsage.inputTokens, 0);
      expect(emptyUsage.outputTokens, 0);
      expect(emptyUsage.totalTokens, 0);
      expect(emptyUsage.cacheReadTokens, 0);
      expect(emptyUsage.isEmpty, isTrue);
      expect(emptyUsage.formatCompact(), 'Usage: N/A');
    });

    test('TokenUsage parses string and dynamic representations safely', () {
      final json = {
        'input_tokens': '1240',
        'output_tokens': '385',
        'total_tokens': '1625',
      };

      final usage = TokenUsage.fromJson(json);
      expect(usage.inputTokens, 1240);
      expect(usage.outputTokens, 385);
      expect(usage.totalTokens, 1625);
      expect(usage.formatCompact(), 'Input: 1,240 | Output: 385 | Total: 1,625');
    });

    test('Context window percentage calculation', () {
      const usageWithLimit = TokenUsage(
        inputTokens: 20000,
        outputTokens: 5000,
        totalTokens: 25000,
        contextWindowLimit: 100000,
      );

      expect(usageWithLimit.contextUsagePercent, 0.25);

      const usageWithoutLimit = TokenUsage(
        inputTokens: 20000,
        outputTokens: 5000,
        totalTokens: 25000,
      );
      expect(usageWithoutLimit.contextUsagePercent, isNull);
    });

    test('Operator + accumulates tokens across responses', () {
      const u1 = TokenUsage(inputTokens: 100, outputTokens: 50, totalTokens: 150, cacheReadTokens: 10);
      const u2 = TokenUsage(inputTokens: 200, outputTokens: 75, totalTokens: 275, cacheReadTokens: 20);

      final combined = u1 + u2;
      expect(combined.inputTokens, 300);
      expect(combined.outputTokens, 125);
      expect(combined.totalTokens, 425);
      expect(combined.cacheReadTokens, 30);
    });
  });

  group('Live Token Updates & Conversation Statistics Tests', () {
    test('Per-message token association and conversation cumulative totals', () async {
      final (_, relay, taskService) = await createConnectedServices();

      // Submit first prompt
      final task1 = await taskService.submitPrompt(
        prompt: 'First prompt',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop',
      );
      final req1 = task1!.requestId;

      // Initially no tokens
      expect(taskService.messages[1].tokenUsage, isNull);
      expect(taskService.conversationTokenUsage.isEmpty, isTrue);

      // 1. Live usage event during stream
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'usage',
        requestId: req1,
        message: '',
        payload: {
          'conversation_id': 'conv-101',
          'usage': {
            'input_tokens': 1000,
            'output_tokens': 100,
            'total_tokens': 1100,
            'cache_read_tokens': 50,
          },
        },
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      final msg1 = taskService.messages[1];
      expect(msg1.tokenUsage, isNotNull);
      expect(msg1.tokenUsage!.inputTokens, 1000);
      expect(msg1.tokenUsage!.outputTokens, 100);
      expect(msg1.tokenUsage!.totalTokens, 1100);
      expect(taskService.conversationTokenUsage.totalTokens, 1100);

      // Completed event with final updated usage
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'completed',
        requestId: req1,
        message: 'Done',
        payload: {
          'conversation_id': 'conv-101',
          'response': 'Final answer 1',
          'usage': {
            'input_tokens': 1000,
            'output_tokens': 150,
            'total_tokens': 1150,
            'cache_read_tokens': 50,
          },
        },
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(taskService.messages[1].tokenUsage!.outputTokens, 150);
      expect(taskService.conversationTokenUsage.totalTokens, 1150);

      // Submit second prompt in same conversation
      final task2 = await taskService.submitPrompt(
        prompt: 'Second prompt',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop',
      );
      final req2 = task2!.requestId;

      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'completed',
        requestId: req2,
        message: 'Done',
        payload: {
          'conversation_id': 'conv-101',
          'response': 'Final answer 2',
          'usage': {
            'input_tokens': 2000,
            'output_tokens': 300,
            'total_tokens': 2300,
            'cache_read_tokens': 100,
          },
        },
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      // Check per-message statistics remain distinct
      final resp1 = taskService.messages[1];
      final resp2 = taskService.messages[3];
      expect(resp1.tokenUsage!.totalTokens, 1150);
      expect(resp2.tokenUsage!.totalTokens, 2300);

      // Conversation cumulative total sums both responses!
      final totalConv = taskService.conversationTokenUsage;
      expect(totalConv.inputTokens, 3000); // 1000 + 2000
      expect(totalConv.outputTokens, 450); // 150 + 300
      expect(totalConv.totalTokens, 3450);  // 1150 + 2300
      expect(totalConv.cacheReadTokens, 150); // 50 + 100

      // Duplicate completed event does not double or corrupt usage
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        event: 'completed',
        requestId: req2,
        message: 'Duplicate event',
        payload: {
          'conversation_id': 'conv-101',
          'response': 'Final answer 2',
          'usage': {
            'input_tokens': 2000,
            'output_tokens': 300,
            'total_tokens': 2300,
            'cache_read_tokens': 100,
          },
        },
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(taskService.conversationTokenUsage.totalTokens, 3450); // Still 3450!

      await relay.disconnect();
    });
  });
}
