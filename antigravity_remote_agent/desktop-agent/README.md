# Antigravity Desktop Agent

A secure Windows background agent that maintains an outbound WebSocket connection to a trusted relay server and brokers approved operations to the local machine.

## ⚠️ Current Status: Mock Mode

This agent starts in **mock mode** by default. It does **not** yet control Antigravity — the Antigravity adapter is a stub that will fail clearly until a real, verified integration is configured.

## Security Model

- **Outbound-only** connections — no inbound ports opened
- **Allowlisted commands** — only pre-approved commands can execute
- **Path traversal protection** — workspace operations are confined to configured roots
- **No `shell=True`** — all commands use argument arrays
- **Audit logging** — all actions are recorded (without secrets)
- **TLS required** — certificate validation is never disabled
- **Exponential backoff** — reconnect logic with jitter

## Setup

### Prerequisites

- Python 3.10+
- pip

### Installation

```powershell
# Clone/copy the repository
cd desktop-agent

# Create virtual environment
python -m venv .venv
.venv\Scripts\Activate.ps1

# Install dependencies
pip install -e ".[dev]"

# Copy and configure environment
copy .env.example .env
# Edit .env with your relay URL, workspace roots, etc.
```

### Configuration

Edit `.env` with your settings:

| Variable | Required | Description |
|---|---|---|
| `RELAY_URL` | Yes | WebSocket URL of the relay server |
| `ENROLLMENT_TOKEN` | Yes* | One-time enrollment token (*mock mode: optional) |
| `WORKSPACE_ROOTS` | Yes | Comma-separated paths the agent may access |
| `ALLOWED_COMMANDS` | No | Commands the agent may execute (default: git status, pytest, ruff check) |
| `MOCK_MODE` | No | Set to `true` for development (default: `true`) |
| `LOG_LEVEL` | No | DEBUG, INFO, WARNING, ERROR (default: INFO) |
| `AUTO_START` | No | Register for Windows startup (default: false) |

See `.env.example` for all options.

### Running

```powershell
# Activate virtual environment
.venv\Scripts\Activate.ps1

# Run the agent
python -m app.main

# Or use the installed entry point
antigravity-agent
```

### Running Tests

```powershell
pytest -v
```

## Architecture

```
app/
├── main.py          # Entry point, logging, task dispatcher
├── config.py        # Pydantic configuration with validation
├── relay.py         # WebSocket client with reconnect & heartbeat
├── security.py      # Path safety, command policy, audit logging
├── workspace.py     # Safe file listing and reading
├── commands.py      # Sandboxed command execution
└── adapters/
    └── antigravity.py  # Stub adapter (reports capabilities honestly)
```

## Supported Operations

| Operation | Description | Status |
|---|---|---|
| `antigravity.prompt` | Send a coding prompt | ⚠️ Stub — requires real integration |
| `workspace.list` | List files in a workspace | ✅ Working |
| `workspace.read` | Read a file's content | ✅ Working |
| `terminal.execute` | Execute an allowlisted command | ✅ Working (allowlist only) |
| `agent.status` | Get agent and adapter status | ✅ Working |

## Uninstall

```powershell
# Stop the agent (Ctrl+C or close the terminal)

# Remove startup registration (if enabled)
powershell -Command "Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'AntigravityAgent' -ErrorAction SilentlyContinue"

# Delete the directory
cd ..
Remove-Item -Recurse -Force desktop-agent
```

## Limitations

- Antigravity integration is a **stub** — it does not yet send prompts or control Antigravity
- Requires a separately deployed relay server
- Mock mode simulates connections but does not send real network traffic
- Windows Credential Manager integration is planned but not yet implemented
