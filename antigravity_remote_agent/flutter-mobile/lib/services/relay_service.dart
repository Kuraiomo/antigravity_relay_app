import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'auth_service.dart';
import '../models/event_model.dart';

/// Connection state for the relay WebSocket.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  unauthorized,
  error;

  String get displayName {
    switch (this) {
      case disconnected:
        return 'Disconnected';
      case connecting:
        return 'Connecting...';
      case connected:
        return 'Connected';
      case reconnecting:
        return 'Reconnecting...';
      case unauthorized:
        return 'Unauthorized';
      case error:
        return 'Error';
    }
  }

  bool get isActive => this == connected;
}

/// Manages the connection to the relay server for live events.
///
/// Supports both Live WebSocket connections and Mock Mode event streaming.
class RelayService extends ChangeNotifier {
  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;
  AuthService? _auth;
  Timer? _reconnectTimer;
  Timer? _mockHeartbeatTimer;
  final List<Timer> _activeMockTimers = [];
  int _reconnectAttempt = 0;
  StreamSubscription? _subscription;

  final List<EventModel> _events = [];
  final StreamController<EventModel> _eventStream =
      StreamController<EventModel>.broadcast();

  // ── Getters ───────────────────────────────────────────

  ConnectionState get state => _state;
  List<EventModel> get events => List.unmodifiable(_events);
  Stream<EventModel> get eventStream => _eventStream.stream;
  bool get isConnected => _state == ConnectionState.connected;

  // ── Auth update ───────────────────────────────────────

  void updateAuth(AuthService auth) {
    _auth = auth;
    if (auth.isAuthenticated && !isConnected && _state != ConnectionState.connecting) {
      connect();
    } else if (!auth.isAuthenticated && isConnected) {
      disconnect();
    }
  }

  // ── Connect ───────────────────────────────────────────

  Future<void> connect() async {
    if (_auth == null || !_auth!.isAuthenticated) {
      _setState(ConnectionState.unauthorized);
      return;
    }

    final relayUrl = _auth!.relayUrl;
    if (relayUrl == null || relayUrl.isEmpty) {
      _setState(ConnectionState.error);
      return;
    }

    _setState(ConnectionState.connecting);

    // If Mock Mode is enabled, simulate instant connection and heartbeats
    if (_auth!.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      _setState(ConnectionState.connected);
      _reconnectAttempt = 0;

      // Add connection event
      final welcomeEvent = EventModel(
        type: 'agent.registered',
        requestId: 'system',
        event: 'connected',
        payload: {
          'message': 'Connected to Antigravity Relay [Mock Mode Active]',
          'device': AuthService.defaultDeviceId,
        },
        timestamp: DateTime.now(),
      );
      _events.add(welcomeEvent);
      _eventStream.add(welcomeEvent);
      notifyListeners();

      _startMockHeartbeat();
      return;
    }

    try {
      final configuredWs = AuthService.defaultRelayWsUrl;
      final rawWs = configuredWs.isNotEmpty
          ? configuredWs
          : '${relayUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://').replaceAll(RegExp(r'/+$'), '')}/ws/mobile';
      final uri = Uri.parse(rawWs);
      final token = AuthService.defaultEnrollmentToken.isNotEmpty
          ? AuthService.defaultEnrollmentToken
          : (_auth?.accessToken ?? '');

      final headers = <String, dynamic>{};
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      _channel = IOWebSocketChannel.connect(
        uri,
        headers: headers.isNotEmpty ? headers : null,
      );

      await _channel!.ready;
      _setState(ConnectionState.connected);
      _reconnectAttempt = 0;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _setState(ConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _startMockHeartbeat() {
    _mockHeartbeatTimer?.cancel();
    _mockHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_state == ConnectionState.connected) {
        debugPrint('[Relay Mock] Heartbeat ping acknowledged');
      }
    });
  }

  // ── Message handling ──────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = EventModel.fromJson(data);
      _events.add(event);
      _eventStream.add(event);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to parse message: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('WebSocket error: $error');
    _setState(ConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WebSocket closed');
    _setState(ConnectionState.disconnected);
    _scheduleReconnect();
  }

  // ── Send message ──────────────────────────────────────

  void send(Map<String, dynamic> message) {
    if (_state != ConnectionState.connected) return;

    if (_auth?.isMockMode == true) {
      _simulateMockTaskResponse(message);
      return;
    }

    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  /// Simulates realistic response streams for tasks in mock mode.
  void _simulateMockTaskResponse(Map<String, dynamic> message) {
    final type = message['type'] as String? ?? '';
    final requestId = message['request_id'] as String? ?? 'req-sim';
    final operation = message['operation'] as String? ?? 'antigravity.prompt';
    final payload = message['payload'] as Map<String, dynamic>? ?? {};

    if (type == 'task.submit') {
      // Step 1: Accepted
      _addMockTimer(const Duration(milliseconds: 300), () {
        _dispatchMockEvent(
          requestId: requestId,
          event: 'accepted',
          message: 'Task accepted by desktop agent',
        );
      });

      // Step 2: Running
      _addMockTimer(const Duration(milliseconds: 800), () {
        _dispatchMockEvent(
          requestId: requestId,
          event: 'running',
          message: 'Executing $operation in workspace...',
        );
      });

      // Step 3 & 4: Output / Progress based on operation
      if (operation == 'antigravity.prompt') {
        final prompt = payload['prompt'] as String? ?? '';
        _addMockTimer(const Duration(milliseconds: 1400), () {
          _dispatchMockEvent(
            requestId: requestId,
            event: 'stdout',
            message: 'Inspecting codebase context and dependencies for: "$prompt"',
          );
        });

        _addMockTimer(const Duration(milliseconds: 2200), () {
          _dispatchMockEvent(
            requestId: requestId,
            event: 'stdout',
            message: 'AI agent generated diff. Workspace changes applied.',
          );
        });

        _addMockTimer(const Duration(milliseconds: 2800), () {
          _dispatchMockEvent(
            requestId: requestId,
            event: 'completed',
            message: 'Coding task completed successfully.',
          );
        });
      } else if (operation == 'terminal.execute') {
        final command = payload['command'] as String? ?? '';
        _addMockTimer(const Duration(milliseconds: 1300), () {
          String output;
          if (command.contains('git status')) {
            output = 'On branch main\nYour branch is up to date with \'origin/main\'.\nnothing to commit, working tree clean';
          } else if (command.contains('pytest')) {
            output = '============================= 42 passed in 0.32s =============================';
          } else {
            output = 'Command executed successfully: $command';
          }

          _dispatchMockEvent(
            requestId: requestId,
            event: 'stdout',
            message: output,
          );
        });

        _addMockTimer(const Duration(milliseconds: 1900), () {
          _dispatchMockEvent(
            requestId: requestId,
            event: 'completed',
            message: 'Process finished with exit code 0.',
          );
        });
      } else {
        _addMockTimer(const Duration(milliseconds: 1500), () {
          _dispatchMockEvent(
            requestId: requestId,
            event: 'completed',
            message: 'Operation $operation completed.',
          );
        });
      }
    }
  }

  void _addMockTimer(Duration duration, void Function() callback) {
    late Timer timer;
    timer = Timer(duration, () {
      _activeMockTimers.remove(timer);
      callback();
    });
    _activeMockTimers.add(timer);
  }

  void _dispatchMockEvent({
    required String requestId,
    required String event,
    required String message,
  }) {
    final eventModel = EventModel(
      type: 'task.event',
      requestId: requestId,
      event: event,
      payload: {'message': message},
      timestamp: DateTime.now(),
    );
    _events.add(eventModel);
    _eventStream.add(eventModel);
    notifyListeners();
  }

  /// Dispatch an event for testing and simulation purposes.
  void dispatchTestEvent(EventModel event) {
    _events.add(event);
    _eventStream.add(event);
    notifyListeners();
  }

  // ── Reconnect ─────────────────────────────────────────

  void _scheduleReconnect() {
    if (_auth?.isMockMode == true) return;

    _reconnectTimer?.cancel();
    _reconnectAttempt++;

    final baseDelay = (1 << _reconnectAttempt.clamp(0, 7)) * 1000;
    final jitter = (baseDelay * 0.3 * (DateTime.now().millisecond / 1000));
    final delay = Duration(milliseconds: baseDelay + jitter.toInt());

    debugPrint(
        'Scheduling reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempt)');
    _setState(ConnectionState.reconnecting);

    _reconnectTimer = Timer(delay, connect);
  }

  // ── Disconnect ────────────────────────────────────────

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _mockHeartbeatTimer?.cancel();
    for (final t in _activeMockTimers) {
      t.cancel();
    }
    _activeMockTimers.clear();
    _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(ConnectionState.disconnected);
  }

  // ── Helpers ───────────────────────────────────────────

  void _setState(ConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _mockHeartbeatTimer?.cancel();
    for (final t in _activeMockTimers) {
      t.cancel();
    }
    _activeMockTimers.clear();
    _subscription?.cancel();
    _channel?.sink.close();
    _eventStream.close();
    super.dispose();
  }
}
