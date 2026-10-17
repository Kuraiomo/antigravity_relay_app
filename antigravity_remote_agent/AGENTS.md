# Antigravity Remote Control — Agent Instructions

## Goal

Build a secure remote-control system with **two separate project directories**:

1. `desktop-agent/` — a quiet Windows background agent that maintains an outbound connection to a trusted relay domain and brokers approved operations to the local machine.
2. `flutter-mobile/` — a Flutter mobile client for sending prompts, viewing live events, choosing projects, browsing permitted files, and requesting approved terminal tasks.

The system must not claim that it controls Antigravity until a real, verified integration is implemented. Prefer supported Antigravity CLI/API/remote-control capabilities. Treat desktop UI automation as a last resort and isolate it behind an adapter.

## Repository layout

Create and maintain these two directories in the repository root:

```text
antigravity-remote/
├── desktop-agent/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── relay.py
│   │   ├── security.py
│   │   ├── workspace.py
│   │   ├── commands.py
│   │   └── adapters/
│   │       ├── __init__.py
│   │       └── antigravity.py
│   ├── tests/
│   ├── .env.example
│   ├── requirements.txt
│   ├── pyproject.toml
│   ├── README.md
│   └── install_windows.ps1
└── flutter-mobile/
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   ├── screens/
    │   ├── services/
    │   └── widgets/
    ├── test/
    ├── pubspec.yaml
    └── README.md
```

Do not put both apps in the same runtime/package. They communicate through a relay API and authenticated WebSocket protocol.

## Architecture and connection

- Flutter client connects to the relay over HTTPS/WSS.
- Windows agent initiates an **outbound WSS connection** to the relay. Do not require inbound router port forwarding or expose a Windows shell to the public internet.
- Relay forwards authenticated, authorized jobs to the agent and streams events back to the correct mobile client.
- For development, the relay may be a separate service. Do not silently pretend the desktop agent itself is a publicly reachable domain.
- Use TLS certificate validation; never disable TLS verification.
- Use device enrollment and short-lived access tokens. Store desktop secrets using Windows Credential Manager or DPAPI in production; `.env` is development-only.
- Support reconnect with exponential backoff and jitter, heartbeat, server-side revocation, and a visible local log file.
- Bind all tasks to an enrolled device, authorized user, and configured workspace.

## Desktop-agent responsibilities

1. Load configuration from environment or a config file; validate required values on startup.
2. Connect outbound to the configured relay, e.g. `wss://remote.example.com/agent/ws`.
3. Authenticate the agent and register a stable device ID.
4. Receive typed task messages; validate schema, request ID, permissions, and workspace.
5. Send status events such as `accepted`, `running`, `stdout`, `stderr`, `completed`, and `failed`.
6. Provide workspace listing and file reading only inside explicitly configured roots.
7. Prevent path traversal, symlink escapes, arbitrary filesystem access, and oversized file reads.
8. Execute only a small configurable command allowlist initially (for example `git status` and `pytest`), using argument arrays, never `shell=True`. Apply timeouts, output limits, and a working-directory allowlist.
9. Require explicit mobile approval for high-risk/destructive operations. Deny privilege escalation, credential extraction, arbitrary PowerShell, and commands outside policy by default.
10. Use an `AntigravityAdapter` interface. Its initial implementation should report which supported integration is configured and fail clearly if none is configured. Do not invent undocumented endpoints or scrape private APIs.
11. Store minimal audit records (timestamp, user/device, action, outcome) without recording secrets or full prompt contents unless explicitly configured.
12. Run as a background process at user level. Windows startup registration must be opt-in and documented; provide a clean stop/uninstall path.

## Flutter client responsibilities

- Provide device connection state and last-seen timestamp.
- Show projects/workspaces, conversations/tasks, streamed events, and clear failure states.
- Allow prompt submission only after selecting an enrolled device and a permitted project.
- Keep conversation/task IDs distinct; do not imply an arbitrary task resumes an existing Antigravity conversation unless the adapter supports that operation.
- Use secure token storage (`flutter_secure_storage` or an equivalent maintained package).
- Use HTTPS/WSS only in production.
- Do not embed relay secrets, Antigravity credentials, or long-lived tokens in the app.
- Implement loading, offline, reconnecting, unauthorized, and task-failed states.
- Confirm before requesting terminal execution and display the exact command/arguments and target workspace.
- Do not store source files or prompt histories longer than necessary without user consent.

## Suggested message protocol

Use versioned JSON messages. Validate every message on both ends.

Agent registration:
```json
{
  "type": "agent.register",
  "protocol_version": 1,
  "device_id": "enrolled-device-id",
  "agent_version": "0.1.0"
}
```

Task request:
```json
{
  "type": "task.submit",
  "request_id": "unique-id",
  "task_id": "server-issued-id",
  "operation": "antigravity.prompt",
  "workspace_id": "configured-workspace-id",
  "payload": {
    "prompt": "Describe the requested coding task"
  }
}
```

Progress event:
```json
{
  "type": "task.event",
  "request_id": "unique-id",
  "task_id": "server-issued-id",
  "event": "running",
  "payload": {
    "message": "Task accepted by desktop agent"
  }
}
```

Never accept a client-supplied arbitrary executable path or raw shell command without policy checks. The relay must authorize a user before routing a request.

## Relay API contract (to implement separately or as an explicitly scoped module)

- `POST /api/devices/enroll` — authenticated one-time enrollment.
- `GET /api/devices` — list devices available to the user.
- `GET /api/projects` — list allowed workspaces for a device.
- `GET /api/tasks/{task_id}` — fetch task state.
- `POST /api/tasks` — submit a typed task request.
- `WS /agent/ws` — outbound connection from desktop agent.
- `WS /client/ws` — live status/events to Flutter.
- `GET /api/projects/{id}/files?path=...` — browse a workspace safely.
- `GET /api/projects/{id}/files/content?path=...` — read a bounded text file.

This guide asks for two client directories. If implementing a relay, put it in a separate `relay-server/` directory only after asking or explicitly expanding scope; don't hide it inside either client.

## Antigravity integration policy

- First inspect official documentation and installed CLI capabilities.
- Use documented CLI/API operations where available.
- Keep provider-specific code in `app/adapters/antigravity.py`.
- If no supported way to send prompts, enumerate the limitation and provide a clearly marked adapter stub.
- UI automation must be optional, local, user-visible when running, and must not bypass authentication, safety prompts, or access controls.
- Do not promise access to private conversation history or exact continuation until verified on the installed version.

## Development workflow

1. Create the two directories and all starter files listed above.
2. Implement config validation, protocol models, relay reconnect logic, logging, and tests in `desktop-agent/`.
3. Implement Flutter screens/services/models and a mock mode in `flutter-mobile/`.
4. Add unit tests for path traversal, command policy, protocol validation, reconnect behavior, and task state transitions.
5. Use mock mode until relay and Antigravity integration are actually configured.
6. Document exact setup commands and required environment variables.
7. Run formatters, static analysis, and tests; report what passed and what remains a stub.
8. Never claim end-to-end functionality without an end-to-end test against a real relay and supported Antigravity integration.

## Acceptance criteria

- Both directories exist and can be developed independently.
- The desktop agent only makes outbound network connections.
- Flutter can authenticate, select the enrolled desktop, submit a mock task, and receive streamed status events.
- Workspace file operations are confined to configured roots.
- Terminal execution is disabled by default and only enabled for allowlisted commands.
- The UI clearly distinguishes mock mode from real Antigravity control.
- Setup, configuration, security limitations, and uninstall steps are documented.
