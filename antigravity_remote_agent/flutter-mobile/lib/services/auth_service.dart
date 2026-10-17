import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Authentication service using secure token storage and .env credentials.
///
/// Stores tokens in platform-secure storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android). Supports auto-login
/// via .env configuration.
class AuthService extends ChangeNotifier {
  static const _keyAccessToken = 'access_token';
  static const _keyRelayUrl = 'relay_url';
  static const _keyUserId = 'user_id';
  static const _keyMockMode = 'mock_mode';
  static const _keyLoggedOut = 'user_explicitly_logged_out';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _relayUrl;
  String? _userId;
  bool _isMockMode = false;
  bool _isLoading = true;
  String? _error;

  // ── Getters ───────────────────────────────────────────

  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;
  bool get isLoading => _isLoading;
  bool get isMockMode => _isMockMode;
  String? get accessToken => _accessToken;
  String? get relayUrl => _relayUrl;
  String? get userId => _userId;
  String? get error => _error;

  // Convenience getters for .env credentials (safe even if dotenv is not loaded)
  static String _getEnv(String key, String fallback) {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env[key] ?? fallback;
      }
    } catch (_) {}
    return fallback;
  }

  static String get defaultRelayUrl =>
      _getEnv('RELAY_URL', 'https://websocket.pagepal.in');
  static String get defaultRelayWsUrl =>
      _getEnv('RELAY_WS_URL', 'wss://websocket.pagepal.in/ws/mobile');
  static String get defaultUsername => _getEnv('USERNAME', 'ayaan');
  static String get defaultPassword =>
      _getEnv('PASSWORD', 'antigravity-remote');
  static String get defaultDeviceId =>
      _getEnv('DEVICE_ID', 'ayaan-windows-pc');
  static String get defaultEnrollmentToken =>
      _getEnv('ENROLLMENT_TOKEN', '');
  static bool get defaultMockMode =>
      _getEnv('MOCK_MODE', 'false').toLowerCase() == 'true';
  static bool get defaultAutoLogin =>
      _getEnv('AUTO_LOGIN', 'true').toLowerCase() == 'true';

  AuthService() {
    _loadStoredCredentials();
  }

  // ── Load stored credentials & Auto-Login ──────────────

  Future<void> _loadStoredCredentials() async {
    try {
      final token = await _storage.read(key: _keyAccessToken);
      final url = await _storage.read(key: _keyRelayUrl);
      final user = await _storage.read(key: _keyUserId);
      final storedMock = await _storage.read(key: _keyMockMode);
      final userLoggedOut = await _storage.read(key: _keyLoggedOut);

      // Only assign if login was not already called while loading
      if (_accessToken == null) {
        if (token != null && token.isNotEmpty) {
          // Restore saved session
          _accessToken = token;
          _relayUrl = url;
          _userId = user;
          _isMockMode = defaultMockMode ? (storedMock != 'false') : false;
        } else if (userLoggedOut != 'true' &&
            defaultAutoLogin &&
            defaultUsername.isNotEmpty &&
            defaultRelayUrl.isNotEmpty) {
          // Automatic login using .env credentials
          _accessToken = defaultEnrollmentToken.isNotEmpty
              ? defaultEnrollmentToken
              : 'env-token-${DateTime.now().millisecondsSinceEpoch}';
          _relayUrl = defaultRelayUrl;
          _userId = defaultUsername;
          _isMockMode = defaultMockMode;
        }
      }
    } catch (e) {
      debugPrint('Note: secure storage not available or empty: $e');
      if (_accessToken == null &&
          defaultAutoLogin &&
          defaultUsername.isNotEmpty &&
          defaultRelayUrl.isNotEmpty) {
        _accessToken = defaultEnrollmentToken.isNotEmpty
            ? defaultEnrollmentToken
            : 'env-token-${DateTime.now().millisecondsSinceEpoch}';
        _relayUrl = defaultRelayUrl;
        _userId = defaultUsername;
        _isMockMode = defaultMockMode;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Login ─────────────────────────────────────────────

  /// Authenticate with the relay server or establish session.
  Future<bool> login({
    required String relayUrl,
    required String username,
    required String password,
    bool mockMode = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cleanUrl = relayUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (cleanUrl.isEmpty || username.isEmpty || password.isEmpty) {
        _error = 'All fields are required';
        return false;
      }

      _isMockMode = mockMode;

      if (mockMode) {
        // Mock authentication — generate session token
        _accessToken = 'mock-token-${DateTime.now().millisecondsSinceEpoch}';
        _relayUrl = cleanUrl;
        _userId = username;

        try {
          await _storage.write(key: _keyAccessToken, value: _accessToken);
          await _storage.write(key: _keyRelayUrl, value: _relayUrl);
          await _storage.write(key: _keyUserId, value: _userId);
          await _storage.write(key: _keyMockMode, value: 'true');
          await _storage.delete(key: _keyLoggedOut);
        } catch (_) {}

        return true;
      }

      // Live relay authentication attempt
      final uri = Uri.parse('$cleanUrl/api/auth/login');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String? ??
            data['token'] as String? ??
            'bearer-${DateTime.now().millisecondsSinceEpoch}';
        _relayUrl = cleanUrl;
        _userId = username;

        try {
          await _storage.write(key: _keyAccessToken, value: _accessToken);
          await _storage.write(key: _keyRelayUrl, value: _relayUrl);
          await _storage.write(key: _keyUserId, value: _userId);
          await _storage.write(key: _keyMockMode, value: 'false');
          await _storage.delete(key: _keyLoggedOut);
        } catch (_) {}

        return true;
      } else {
        _error = 'Authentication failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : "Unauthorized"}';
        return false;
      }
    } catch (e) {
      _error = 'Connection failed: $e. You can toggle Mock Mode to continue testing.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Logout ────────────────────────────────────────────

  Future<void> logout() async {
    _accessToken = null;
    _relayUrl = null;
    _userId = null;
    _error = null;

    try {
      await _storage.deleteAll();
      await _storage.write(key: _keyLoggedOut, value: 'true');
    } catch (_) {}
    notifyListeners();
  }
}
