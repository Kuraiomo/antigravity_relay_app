import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/main.dart';

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

  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const AntigravityApp());
    expect(find.byType(AntigravityApp), findsOneWidget);
  });
}
