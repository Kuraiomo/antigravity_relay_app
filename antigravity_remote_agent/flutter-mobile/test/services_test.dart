import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/services/auth_service.dart';
import 'package:antigravity_mobile/services/relay_service.dart';
import 'package:antigravity_mobile/services/device_service.dart';
import 'package:antigravity_mobile/services/task_service.dart';
import 'package:antigravity_mobile/models/task_model.dart';

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

  group('AuthService Tests', () {
    test('Auto-login succeeds with .env credentials', () async {
      final auth = AuthService();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(auth.isAuthenticated, isTrue);
      expect(auth.userId, 'ayaan');
      expect(auth.relayUrl, 'https://websocket.pagepal.in');
    });

    test('Login with mock mode succeeds', () async {
      final auth = AuthService();
      final success = await auth.login(
        relayUrl: 'https://websocket.pagepal.in',
        username: 'ayaan',
        password: 'password123',
        mockMode: true,
      );

      expect(success, isTrue, reason: auth.error);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.userId, 'ayaan');
      expect(auth.relayUrl, 'https://websocket.pagepal.in');
      expect(auth.isMockMode, isTrue);
    });

    test('Login with empty fields fails with error', () async {
      final auth = AuthService();
      final success = await auth.login(
        relayUrl: '',
        username: '',
        password: '',
        mockMode: true,
      );

      expect(success, isFalse);
      expect(auth.error, contains('required'));
    });

    test('Logout clears credentials', () async {
      final auth = AuthService();
      await auth.login(
        relayUrl: 'https://websocket.pagepal.in',
        username: 'testuser',
        password: 'pwd',
        mockMode: true,
      );
      expect(auth.isAuthenticated, isTrue);

      await auth.logout();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.accessToken, isNull);
    });
  });

  group('RelayService Tests', () {
    test('Connects and updates state in mock mode', () async {
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
      expect(relay.isConnected, isTrue);
      expect(relay.state, ConnectionState.connected);
      expect(relay.events.isNotEmpty, isTrue);

      await relay.disconnect();
      expect(relay.isConnected, isFalse);
      expect(relay.state, ConnectionState.disconnected);
    });
  });

  group('DeviceService Tests', () {
    test('Loads enrolled devices and workspaces', () async {
      final auth = AuthService();
      await auth.login(
        relayUrl: 'https://websocket.pagepal.in',
        username: 'ayaan',
        password: 'pwd',
        mockMode: true,
      );

      final deviceService = DeviceService();
      deviceService.updateAuth(auth);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(deviceService.devices.isNotEmpty, isTrue);
      expect(deviceService.selectedDevice, isNotNull);
      expect(deviceService.selectedDevice!.id, 'ayaan-windows-pc');

      expect(deviceService.projects.isNotEmpty, isTrue);
      expect(deviceService.selectedProject, isNotNull);
      expect(deviceService.hasSelection, isTrue);
    });
  });

  group('TaskService Tests', () {
    test('Submits task and processes streamed events', () async {
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

      final task = await taskService.submitPrompt(
        prompt: 'Refactor agent loop',
        deviceId: 'ayaan-windows-pc',
        workspaceId: r'C:\Users\ayaan\OneDrive\Desktop',
      );

      expect(task, isNotNull);
      expect(taskService.tasks.length, 1);
      expect(taskService.activeTask?.requestId, task?.requestId);

      // Wait for mock events to arrive
      await Future.delayed(const Duration(milliseconds: 1000));
      expect(taskService.activeTask?.events.isNotEmpty, isTrue);
      expect(taskService.activeTask?.status, isNot(TaskStatus.pending));

      await relay.disconnect();
    });
  });
}
