import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:antigravity_mobile/models/event_model.dart';
import 'package:antigravity_mobile/screens/task_screen.dart';
import 'package:antigravity_mobile/services/auth_service.dart';
import 'package:antigravity_mobile/services/device_service.dart';
import 'package:antigravity_mobile/services/relay_service.dart';
import 'package:antigravity_mobile/services/task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
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

  Future<(AuthService, RelayService, DeviceService, TaskService)> createConnectedServices() async {
    final auth = AuthService();
    await auth.login(
      relayUrl: 'https://websocket.pagepal.in',
      username: 'ayaan',
      password: 'pwd',
      mockMode: true,
    );

    final relay = RelayService();
    relay.updateAuth(auth);
    await Future.delayed(const Duration(milliseconds: 300));

    final deviceService = DeviceService();
    deviceService.updateAuth(auth);

    final taskService = TaskService();
    taskService.updateDependencies(auth, relay);

    return (auth, relay, deviceService, taskService);
  }

  group('Permission Mode & Full Auto Service Tests', () {
    test('Default permission mode is request-review', () async {
      final (_, relay, deviceService, taskService) = await createConnectedServices();
      expect(taskService.permissionMode, 'request-review');
      expect(taskService.effectivePermissionMode, isNull);
      expect(taskService.isPermissionModeMismatch, isFalse);
      await relay.disconnect();
      taskService.dispose();
      deviceService.dispose();
    });

    test('Mode changes and persists across submissions', () async {
      final (_, relay, deviceService, taskService) = await createConnectedServices();

      taskService.setPermissionMode('full-auto');
      expect(taskService.permissionMode, 'full-auto');

      taskService.setPermissionMode('accept-edits');
      expect(taskService.permissionMode, 'accept-edits');

      taskService.setPermissionMode('request-review');
      expect(taskService.permissionMode, 'request-review');

      await relay.disconnect();
      taskService.dispose();
      deviceService.dispose();
    });

    test('Detects mismatch when effective CLI mode differs from requested mode', () async {
      final (_, relay, deviceService, taskService) = await createConnectedServices();

      taskService.setPermissionMode('full-auto');

      // Simulate a completed event where CLI returned request-review instead
      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        requestId: 'req-mismatch',
        taskId: 'task-mismatch',
        event: 'completed',
        message: 'Task completed',
        payload: {
          'conversation_id': 'conv-123',
          'effective_permission_mode': 'request-review',
        },
        timestamp: DateTime.now(),
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(taskService.effectivePermissionMode, 'request-review');
      expect(taskService.isPermissionModeMismatch, isTrue);

      // Starting new conversation resets effective mode
      taskService.startNewConversation();
      expect(taskService.effectivePermissionMode, isNull);
      expect(taskService.isPermissionModeMismatch, isFalse);

      await relay.disconnect();
      taskService.dispose();
      deviceService.dispose();
    });

    test('No mismatch when full-auto matches always-proceed', () async {
      final (_, relay, deviceService, taskService) = await createConnectedServices();

      taskService.setPermissionMode('full-auto');

      relay.dispatchTestEvent(EventModel(
        type: 'task.event',
        requestId: 'req-match',
        taskId: 'task-match',
        event: 'completed',
        message: 'Task completed',
        payload: {
          'conversation_id': 'conv-123',
          'effective_permission_mode': 'always-proceed',
        },
        timestamp: DateTime.now(),
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(taskService.effectivePermissionMode, 'always-proceed');
      expect(taskService.isPermissionModeMismatch, isFalse);

      await relay.disconnect();
      taskService.dispose();
      deviceService.dispose();
    });
  });

  group('TaskScreen UI Navigation & Permission Panel Widget Tests', () {
    testWidgets('Navigation panel is collapsed by default and shows active permission chip', (tester) async {
      final auth = AuthService();
      final relay = RelayService();
      final deviceService = DeviceService();
      final taskService = TaskService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: relay),
            ChangeNotifierProvider.value(value: deviceService),
            ChangeNotifierProvider.value(value: taskService),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TaskScreen()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Top collapsed bar contains expand chevron and Controls icon
      expect(find.byIcon(Icons.tune_rounded), findsWidgets);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      // Status bar shows "Review" chip even when collapsed
      expect(find.text('Review'), findsWidgets);

      // Expanded controls header is not shown (collapsed initially)
      expect(find.text('Collapse'), findsNothing);

      // Tap to expand
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Now expanded controls header is visible
      expect(find.text('Environment & Controls'), findsOneWidget);
      expect(find.text('Collapse'), findsOneWidget);

      // Shows all 3 permission options: Review, Edit, Full Auto
      expect(find.text('Full Auto'), findsWidgets);
      expect(find.text('Edit'), findsWidgets);

      // Tap Collapse
      await tester.tap(find.text('Collapse'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Collapsed again
      expect(find.text('Environment & Controls'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      taskService.dispose();
      deviceService.dispose();
      relay.dispose();
    });
  });
}
