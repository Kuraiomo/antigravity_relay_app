"""Antigravity Desktop Agent — main entry point.

Starts the background agent:
1. Loads and validates configuration.
2. Sets up logging and audit trail.
3. Initialises the Antigravity adapter (stub).
4. Connects to the relay (or mock relay).
5. Dispatches incoming tasks to the appropriate handler.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import signal
import sys
from pathlib import Path

# Ensure desktop-agent root is in sys.path when running app/main.py directly
_root = Path(__file__).resolve().parent.parent
if str(_root) not in sys.path:
    sys.path.insert(0, str(_root))

from typing import Any

from app import __version__
from app.adapters.antigravity import AntigravityAdapter
from app.commands import execute_command
from app.config import AgentConfig, load_config
from app.relay import MockRelayClient, RelayClient
from app.security import (
    audit,
    configure_audit_log,
    validate_permission_mode,
    validate_request_id,
    validate_workspace_id,
)
from app.workspace import list_files, read_file

logger = logging.getLogger("agent")


# ── Logging setup ────────────────────────────────────────────────────────────


def _setup_logging(config: AgentConfig) -> None:
    """Configure root logger with file and console handlers."""
    level = getattr(logging, config.log_level, logging.INFO)

    formatter = logging.Formatter(
        "%(asctime)s | %(levelname)-8s | %(name)-20s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Console handler
    console = logging.StreamHandler(sys.stdout)
    console.setLevel(level)
    console.setFormatter(formatter)

    # File handler
    file_handler = logging.FileHandler(config.log_file, encoding="utf-8")
    file_handler.setLevel(level)
    file_handler.setFormatter(formatter)

    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(console)
    root.addHandler(file_handler)


# ── Task dispatcher ─────────────────────────────────────────────────────────


class TaskDispatcher:
    """Routes incoming task messages to the right handler."""

    def __init__(
        self,
        config: AgentConfig,
        relay: RelayClient,
        adapter: AntigravityAdapter,
    ) -> None:
        self.config = config
        self.relay = relay
        self.adapter = adapter
        self._workspace_roots = config.resolved_workspace_roots()

    async def handle_task(self, message: dict[str, Any]) -> None:
        """Dispatch a task message from the relay."""
        request_id = message.get("request_id", "")
        task_id = message.get("task_id", "")
        operation = message.get("operation", "")
        workspace_id = message.get("workspace_id", "")
        payload = message.get("payload", {})

        # Validate request ID
        if not validate_request_id(request_id):
            await self.relay.send_event(
                request_id or "invalid",
                task_id or "unknown",
                "failed",
                {"message": "Invalid request ID"},
            )
            return

        # Accept the task
        await self.relay.send_event(request_id, task_id, "accepted", {"message": "Task accepted"})

        try:
            if operation == "antigravity.prompt":
                await self._handle_prompt(request_id, task_id, workspace_id, payload)
            elif operation in ("workspace.roots", "workspaces.list"):
                await self._handle_workspace_roots(request_id, task_id)
            elif operation == "workspace.list":
                await self._handle_workspace_list(request_id, task_id, workspace_id, payload)
            elif operation == "workspace.read":
                await self._handle_workspace_read(request_id, task_id, workspace_id, payload)
            elif operation == "terminal.execute":
                await self._handle_terminal(request_id, task_id, workspace_id, payload)
            elif operation == "agent.status":
                await self._handle_status(request_id, task_id)
            else:
                await self.relay.send_event(
                    request_id,
                    task_id,
                    "failed",
                    {"message": f"Unknown operation: {operation}"},
                )
        except Exception as exc:
            logger.exception("Task handler error: %s", exc)
            await self.relay.send_event(
                request_id,
                task_id,
                "failed",
                {"message": f"Internal error: {type(exc).__name__}"},
            )

    async def _handle_prompt(
        self,
        request_id: str,
        task_id: str,
        workspace_id: str,
        payload: dict[str, Any],
    ) -> None:
        """Handle an Antigravity prompt request."""
        prompt = payload.get("prompt", "")
        if not prompt:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": "Empty prompt"}
            )
            return

        if workspace_id:
            workspace_root = validate_workspace_id(workspace_id, self._workspace_roots)
        elif self._workspace_roots:
            workspace_root = self._workspace_roots[0]
        else:
            workspace_root = None

        if workspace_root is None:
            await self.relay.send_event(
                request_id,
                task_id,
                "failed",
                {
                    "message": f"Workspace directory does not exist, is inaccessible, or is not in allowed roots: {workspace_id or '(none)'}"
                },
            )
            return

        # Optional conversation ID from payload (allows client to resume/reset)
        conversation_id = payload.get("conversation_id")
        if payload.get("reset_conversation") or payload.get("new_conversation"):
            self.adapter.set_conversation_id(None, str(workspace_root))
            conversation_id = None

        raw_permission_mode = payload.get("permission_mode", "request-review")
        validated_permission_mode = validate_permission_mode(raw_permission_mode)
        if validated_permission_mode is None:
            await self.relay.send_event(
                request_id,
                task_id,
                "failed",
                {
                    "message": f"Unsupported or invalid permission mode: '{raw_permission_mode}'. Must be one of: 'request-review' (or 'review'), 'accept-edits' (or 'edit'), 'full-auto'.",
                    "conversation_id": conversation_id or "",
                    "requested_permission_mode": raw_permission_mode,
                },
            )
            return

        permission_mode = validated_permission_mode

        await self.relay.send_event(
            request_id, task_id, "running", {"message": "Thinking..."}
        )

        async def on_delta(delta: str, conv_id: str) -> None:
            await self.relay.send_event(
                request_id,
                task_id,
                "stdout",
                {"message": delta, "conversation_id": conv_id},
            )

        async def on_usage(usage_data: dict[str, int], conv_id: str) -> None:
            await self.relay.send_event(
                request_id,
                task_id,
                "usage",
                {"usage": usage_data, "conversation_id": conv_id},
            )

        effective_workspace = str(workspace_root)

        result = await self.adapter.send_prompt(
            prompt,
            workspace=effective_workspace,
            on_delta=on_delta,
            conversation_id=conversation_id,
            on_usage=on_usage,
            permission_mode=permission_mode,
        )

        conv_id = result.data.get("conversation_id", "")
        streamed = result.data.get("streamed", False)
        final_response = result.data.get("response", result.message)
        usage_data = result.data.get("usage")
        effective_perm_mode = result.data.get("effective_permission_mode", permission_mode)
        requested_perm_mode = result.data.get("requested_permission_mode", permission_mode)

        if result.success:
            event_payload: dict[str, Any] = {
                "conversation_id": conv_id,
                "response": final_response,
                "effective_permission_mode": effective_perm_mode,
                "requested_permission_mode": requested_perm_mode,
            }
            if usage_data:
                event_payload["usage"] = usage_data

            if streamed:
                # Do not emit the final response twice if already streamed
                event_payload["message"] = "Task completed"
            else:
                event_payload["message"] = final_response

            await self.relay.send_event(
                request_id,
                task_id,
                "completed",
                event_payload,
            )
        else:
            fail_payload: dict[str, Any] = {
                "message": result.message,
                "conversation_id": conv_id,
                "effective_permission_mode": effective_perm_mode,
                "requested_permission_mode": requested_perm_mode,
            }
            if usage_data:
                fail_payload["usage"] = usage_data

            await self.relay.send_event(
                request_id,
                task_id,
                "failed",
                fail_payload,
            )

    async def _handle_workspace_list(
        self,
        request_id: str,
        task_id: str,
        workspace_id: str,
        payload: dict[str, Any],
    ) -> None:
        """Handle a workspace file listing request."""
        workspace_root = validate_workspace_id(workspace_id, self._workspace_roots)
        if workspace_root is None:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": "Invalid or unauthorized workspace"}
            )
            return

        relative_path = payload.get("path", "")
        result = list_files(workspace_root, relative_path, self._workspace_roots)

        if "error" in result:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": result["error"]}
            )
        else:
            await self.relay.send_event(
                request_id, task_id, "completed", {"message": "File listing", "data": result}
            )

    async def _handle_workspace_read(
        self,
        request_id: str,
        task_id: str,
        workspace_id: str,
        payload: dict[str, Any],
    ) -> None:
        """Handle a workspace file read request."""
        workspace_root = validate_workspace_id(workspace_id, self._workspace_roots)
        if workspace_root is None:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": "Invalid or unauthorized workspace"}
            )
            return

        relative_path = payload.get("path", "")
        if not relative_path:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": "No file path specified"}
            )
            return

        result = read_file(
            workspace_root,
            relative_path,
            self._workspace_roots,
            max_size=self.config.max_file_size,
        )

        if "error" in result:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": result["error"]}
            )
        else:
            await self.relay.send_event(
                request_id,
                task_id,
                "completed",
                {"message": "File content", "data": result},
            )

    async def _handle_terminal(
        self,
        request_id: str,
        task_id: str,
        workspace_id: str,
        payload: dict[str, Any],
    ) -> None:
        """Handle a terminal command execution request."""
        workspace_root = validate_workspace_id(workspace_id, self._workspace_roots)
        if workspace_root is None:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": "Invalid or unauthorized workspace"}
            )
            return

        command = payload.get("command", "")
        if not command:
            await self.relay.send_event(
                request_id, task_id, "failed", {"message": "No command specified"}
            )
            return

        audit(
            device=self.config.device_id,
            action="terminal.execute",
            outcome="processing",
            details={"command": command, "workspace": workspace_id},
        )

        allowed_cmds = (
            self.config.allowed_commands
            if isinstance(self.config.allowed_commands, list)
            else [self.config.allowed_commands]
        )

        async for event in execute_command(
            command_line=command,
            working_directory=workspace_root,
            allowed_commands=allowed_cmds,
            allowed_roots=self._workspace_roots,
            timeout=self.config.command_timeout,
            max_output=self.config.max_output_size,
            device_id=self.config.device_id,
        ):
            await self.relay.send_event(
                request_id,
                task_id,
                event.get("event", "running"),
                {k: v for k, v in event.items() if k != "event"},
            )

    async def _handle_workspace_roots(self, request_id: str, task_id: str) -> None:
        """Handle a request to list configured and accessible workspace roots."""
        workspaces: list[dict[str, Any]] = []
        seen_paths: set[str] = set()

        for root in self._workspace_roots:
            p = root.resolve()
            p_str = str(p)
            if p.is_dir() and p_str not in seen_paths:
                seen_paths.add(p_str)
                workspaces.append({
                    "id": p_str,
                    "name": p.name or p_str,
                    "path": p_str,
                    "exists": True,
                })
                # Discover immediate project subdirectories
                try:
                    for child in p.iterdir():
                        if child.is_dir() and not child.name.startswith("."):
                            c_str = str(child.resolve())
                            if c_str not in seen_paths:
                                seen_paths.add(c_str)
                                workspaces.append({
                                    "id": c_str,
                                    "name": child.name,
                                    "path": c_str,
                                    "exists": True,
                                })
                except OSError:
                    pass

        await self.relay.send_event(
            request_id,
            task_id,
            "completed",
            {
                "message": f"Found {len(workspaces)} configured workspaces",
                "data": {"workspaces": workspaces},
            },
        )

    async def _handle_status(self, request_id: str, task_id: str) -> None:
        """Handle an agent status request."""
        adapter_status = await self.adapter.get_status()
        workspaces = [
            {"id": str(r.resolve()), "name": r.name or str(r), "path": str(r.resolve())}
            for r in self._workspace_roots
            if r.is_dir()
        ]
        await self.relay.send_event(
            request_id,
            task_id,
            "completed",
            {
                "message": "Agent status",
                "data": {
                    "agent_version": __version__,
                    "device_id": self.config.device_id,
                    "mock_mode": self.config.mock_mode,
                    "connected": self.relay.is_connected,
                    "workspaces": [w["path"] for w in workspaces],
                    "workspace_list": workspaces,
                    "adapter": adapter_status.data,
                },
            },
        )


# ── Main entry point ────────────────────────────────────────────────────────


async def _run(config: AgentConfig) -> None:
    """Async main loop."""
    adapter = AntigravityAdapter()
    status = await adapter.get_status()
    logger.info("Adapter status: %s", status.message)

    # Create relay client
    if config.mock_mode:
        relay: RelayClient = MockRelayClient(
            url=config.relay_url,
            device_id=config.device_id,
            agent_version=__version__,
            agent_secret=config.agent_secret,
            heartbeat_interval=config.heartbeat_interval,
        )
    else:
        relay = RelayClient(
            url=config.relay_url,
            device_id=config.device_id,
            agent_version=__version__,
            agent_secret=config.agent_secret or config.enrollment_token,
            heartbeat_interval=config.heartbeat_interval,
            mock_mode=False,
        )

    # Wire up task handler
    dispatcher = TaskDispatcher(config, relay, adapter)
    relay.set_task_handler(dispatcher.handle_task)

    # Handle shutdown signals
    loop = asyncio.get_running_loop()
    shutdown_event = asyncio.Event()

    def _signal_handler() -> None:
        logger.info("Shutdown signal received")
        shutdown_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(sig, _signal_handler)

    # Start relay connection
    relay_task = asyncio.create_task(relay.connect())

    logger.info("═══════════════════════════════════════════")
    logger.info("  Antigravity Desktop Agent v%s", __version__)
    logger.info("  Device: %s", config.device_id)
    logger.info("  Mode: %s", "MOCK" if config.mock_mode else "LIVE")
    logger.info("═══════════════════════════════════════════")

    try:
        # Wait for shutdown signal or relay task to end
        done, pending = await asyncio.wait(
            [relay_task, asyncio.create_task(shutdown_event.wait())],
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()
    finally:
        await relay.disconnect()
        logger.info("Agent stopped")


def main() -> None:
    """Synchronous entry point."""
    try:
        config = load_config()
    except Exception as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        sys.exit(1)

    _setup_logging(config)
    configure_audit_log(config.log_file.replace(".log", ".audit.jsonl"))

    logger.info("Starting Antigravity Desktop Agent...")
    try:
        asyncio.run(_run(config))
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as exc:
        logger.exception("Fatal error: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
