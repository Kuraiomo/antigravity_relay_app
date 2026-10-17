# Antigravity Mobile — Flutter Client

A Flutter mobile client for remotely controlling an enrolled desktop agent through a secure relay server.

## ⚠️ Current Status: Mock Mode

This client starts in **mock mode** by default. It uses simulated devices and projects for development. It does **not** claim to control Antigravity until a real, verified integration is configured on the desktop agent.

## Features

- **Device Management** — View enrolled devices with online status and last-seen timestamps
- **Project Selection** — Choose from permitted workspaces on the selected device
- **Prompt Submission** — Send coding task prompts (requires device + project selection)
- **Terminal Commands** — Execute allowlisted commands with confirmation dialog showing exact command, arguments, and target workspace
- **Live Events** — Stream and display real-time task status events
- **File Browser** — Browse workspace files safely (confined to configured roots)
- **Connection States** — Loading, offline, reconnecting, unauthorized, and task-failed states
- **Secure Storage** — Tokens stored via `flutter_secure_storage` (Keychain/EncryptedSharedPreferences)

## Security

- **HTTPS/WSS only** in production
- **No embedded secrets** — relay URLs and tokens are entered by the user and stored securely
- **No long-lived tokens** — access tokens are short-lived
- **Command confirmation** — terminal execution requires explicit approval with full command display
- **No source file caching** — does not store source files or prompt histories longer than necessary

## Setup

### Prerequisites

- Flutter SDK 3.2+
- Android Studio or Xcode (for device/emulator)

### Installation

```bash
cd flutter-mobile

# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Run tests
flutter test
```

### Configuration

The relay URL is configured at login time. No configuration files need to be pre-populated.

## Architecture

```
lib/
├── main.dart              # App entry point, theme, auth gate
├── models/
│   ├── device_model.dart  # Enrolled device data
│   ├── task_model.dart    # Task with status and events
│   ├── project_model.dart # Workspace/project data
│   └── event_model.dart   # Relay event data
├── screens/
│   ├── login_screen.dart  # Authentication with relay URL
│   ├── home_screen.dart   # Main screen with bottom nav
│   ├── task_screen.dart   # Prompt/command submission & tracking
│   ├── events_screen.dart # Live event stream
│   └── files_screen.dart  # Remote file browser
├── services/
│   ├── auth_service.dart  # Secure auth with token storage
│   ├── relay_service.dart # WebSocket connection management
│   ├── device_service.dart # Device/project management
│   └── task_service.dart  # Task submission and tracking
└── widgets/
    ├── connection_indicator.dart # Animated connection state
    ├── device_selector.dart     # Device/project picker
    ├── mock_mode_banner.dart    # Mock mode indicator
    └── task_event_list.dart     # Task output display
```

## State Management

Uses **Provider** with `ChangeNotifier` for reactive state. Services are wired via `ChangeNotifierProxyProvider` for dependency injection.

## Mock Mode vs Real Mode

| Feature | Mock Mode | Real Mode |
|---|---|---|
| Authentication | Accepts any credentials | Relay API authentication |
| Devices | Simulated device list | `GET /api/devices` |
| Projects | Simulated project list | `GET /api/projects` |
| Events | None (no real relay) | Live WSS stream |
| Antigravity | Stub adapter response | Real adapter integration |

The UI clearly distinguishes mock mode with an amber banner at the top of every screen.

## Limitations

- WebSocket connection requires a running relay server for real mode
- File browser is currently mock data only
- Antigravity prompt submission depends on the desktop agent's adapter implementation
- No offline queue for tasks submitted while disconnected
