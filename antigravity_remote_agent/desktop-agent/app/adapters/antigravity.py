"""Antigravity adapter — isolated integration point.

All provider-specific code lives here.  The adapter exposes a clean
interface; the rest of the agent treats it as a black box.

IMPORTANT: This is a **stub** implementation.  It does NOT yet integrate
with the real Antigravity CLI or API.  It reports its capabilities
honestly and fails clearly when no supported integration is configured.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


@dataclass
class AdapterCapability:
    """Describes what the adapter can (and cannot) do."""

    name: str
    supported: bool
    description: str


@dataclass
class AdapterResult:
    """Result of an adapter operation."""

    success: bool
    operation: str
    message: str
    data: dict[str, Any] = field(default_factory=dict)


class AntigravityAdapterBase(ABC):
    """Abstract base class for Antigravity integrations."""

    @abstractmethod
    def get_capabilities(self) -> list[AdapterCapability]:
        """Return the list of capabilities this adapter supports."""
        ...

    @abstractmethod
    async def send_prompt(
        self,
        prompt: str,
        workspace: str = "",
        on_delta: Callable[[str, str], Awaitable[None]] | None = None,
        conversation_id: str | None = None,
    ) -> AdapterResult:
        """Send a coding prompt to Antigravity."""
        ...

    @abstractmethod
    async def get_status(self) -> AdapterResult:
        """Return the current integration status."""
        ...


class AntigravityAdapter(AntigravityAdapterBase):
    """Official Antigravity CLI adapter using `agy.exe`.

    Executes prompts non-interactively using:
        agy.exe --print <prompt> --output-format stream-json --print-timeout 0
    Optionally resumes conversations with:
        --conversation <conversation_id>
    Streams assistant response deltas in real-time.
    """

    def __init__(self) -> None:
        self._configured = False
        self._integration_type: str | None = None
        self._binary_path: str | None = None
        self._conversations: dict[str, str] = {}
        self._last_conversation_id: str | None = None
        self._detect_integration()

    def get_conversation_id(self, workspace: str | None = None) -> str | None:
        """Return the active conversation ID for a workspace or global."""
        if workspace and workspace in self._conversations:
            return self._conversations[workspace]
        return self._last_conversation_id

    def set_conversation_id(self, conversation_id: str | None, workspace: str | None = None) -> None:
        """Set or clear the active conversation ID."""
        if conversation_id is None:
            if workspace:
                self._conversations.pop(workspace, None)
            self._last_conversation_id = None
            return
        if workspace:
            self._conversations[workspace] = conversation_id
        self._last_conversation_id = conversation_id

    def _detect_integration(self) -> None:
        """Attempt to detect the official Antigravity CLI.

        Checks:
        1. ANTIGRAVITY_PATH or ANTIGRAVITY_CLI environment variable override
        2. Official Antigravity CLI at %LOCALAPPDATA%\\agy\\bin\\agy.exe
        3. agy on PATH
        4. Fallbacks (antigravity, antigravity-ide)
        """
        # 1. Custom env var override
        env_path = os.environ.get("ANTIGRAVITY_PATH") or os.environ.get("ANTIGRAVITY_CLI")
        if env_path and Path(env_path).exists():
            self._configured = True
            self._integration_type = "env_override"
            self._binary_path = env_path
            logger.info("AntigravityAdapter: Configured via ANTIGRAVITY_PATH=%s", env_path)
            return

        # 2. Official Antigravity CLI at %LOCALAPPDATA%\agy\bin\agy.exe
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            official_cli = Path(local_app_data) / "agy" / "bin" / "agy.exe"
            if official_cli.exists():
                self._configured = True
                self._integration_type = "cli (agy)"
                self._binary_path = str(official_cli)
                logger.info("AntigravityAdapter: Detected official Antigravity CLI at %s", official_cli)
                return

        # 3. Check agy on PATH
        agy_cmd = shutil.which("agy")
        if agy_cmd:
            self._configured = True
            self._integration_type = "cli (agy)"
            self._binary_path = agy_cmd
            logger.info("AntigravityAdapter: Detected agy on PATH: %s", agy_cmd)
            return

        # 4. Fallback: check other CLI names on PATH
        for cmd in ("antigravity", "antigravity-ide"):
            found = shutil.which(cmd)
            if found:
                self._configured = True
                self._integration_type = f"cli ({cmd})"
                self._binary_path = found
                logger.info("AntigravityAdapter: Detected CLI on PATH: %s", found)
                return

        # 5. Fallback: check standard Windows LocalAppData install locations
        if local_app_data:
            candidate_paths = [
                Path(local_app_data) / "Programs" / "Antigravity IDE" / "bin" / "antigravity-ide.cmd",
                Path(local_app_data) / "Programs" / "Antigravity IDE" / "Antigravity IDE.exe",
                Path(local_app_data) / "Programs" / "Antigravity" / "Antigravity.exe",
            ]
            for candidate in candidate_paths:
                if candidate.exists():
                    self._configured = True
                    self._integration_type = f"ide ({candidate.name})"
                    self._binary_path = str(candidate)
                    logger.info("AntigravityAdapter: Detected Antigravity IDE at %s", candidate)
                    return

        logger.info(
            "AntigravityAdapter: No supported integration detected. "
            "Running in stub mode. Configure a real integration or ANTIGRAVITY_PATH to enable "
            "actual Antigravity control."
        )

    def get_capabilities(self) -> list[AdapterCapability]:
        """Report capabilities honestly."""
        return [
            AdapterCapability(
                name="send_prompt",
                supported=self._configured,
                description=(
                    "Send a coding prompt to Antigravity. "
                    f"{'Configured via ' + (self._integration_type or 'unknown') if self._configured else 'NOT CONFIGURED — stub only.'}"
                ),
            ),
            AdapterCapability(
                name="stream_events",
                supported=self._configured,
                description="Stream text deltas incrementally via NDJSON stream-json output.",
            ),
            AdapterCapability(
                name="resume_conversation",
                supported=self._configured,
                description="Resume previous conversation using --conversation flag.",
            ),
        ]

    async def send_prompt(
        self,
        prompt: str,
        workspace: str = "",
        on_delta: Callable[[str, str], Awaitable[None]] | None = None,
        conversation_id: str | None = None,
        on_usage: Callable[[dict[str, int], str], Awaitable[None]] | None = None,
        permission_mode: str = "request-review",
    ) -> AdapterResult:
        """Send a prompt using agy.exe with NDJSON event streaming."""
        if not self._configured or not self._binary_path:
            return AdapterResult(
                success=False,
                operation="send_prompt",
                message=(
                    "Antigravity integration is not configured. "
                    "Install and configure a supported integration "
                    "(CLI, API) before using this feature. "
                    "This is a stub — it does NOT control Antigravity."
                ),
            )

        # Verify workspace existence if specified
        working_dir: str | None = None
        if workspace:
            wp = Path(workspace).resolve()
            if not wp.exists() or not wp.is_dir():
                return AdapterResult(
                    success=False,
                    operation="send_prompt",
                    message=f"Workspace directory does not exist or is not accessible: {workspace}",
                    data={"workspace": workspace, "conversation_id": active_conv_id or ""},
                )
            working_dir = str(wp)

        active_conv_id = conversation_id or self.get_conversation_id(workspace)

        cmd = [
            self._binary_path,
            "--print",
            prompt,
            "--output-format",
            "stream-json",
            "--print-timeout",
            "0",
        ]

        norm_mode = (permission_mode or "request-review").strip().lower()
        if norm_mode in ("review", "request-review"):
            # Default Review mode — require approvals, no dangerous flags
            pass
        elif norm_mode in ("edit", "accept-edits"):
            # Edit mode — allow supported file edits without interactive prompt
            cmd.extend(["--mode", "accept-edits"])
        elif norm_mode in ("full-auto", "full_auto", "auto"):
            # Full Auto — use verified official CLI auto-approval mechanism
            cmd.append("--dangerously-skip-permissions")
        else:
            return AdapterResult(
                success=False,
                operation="send_prompt",
                message=f"Unsupported permission mode: '{permission_mode}'. Valid modes: review, edit, full-auto.",
                data={"conversation_id": active_conv_id or ""},
            )

        if working_dir:
            cmd.extend(["--add-dir", working_dir])
        if active_conv_id:
            cmd.extend(["--conversation", active_conv_id])

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=working_dir,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            # Drain stderr asynchronously to prevent pipe buffer deadlocks
            stderr_chunks: list[bytes] = []

            async def _drain_stderr() -> None:
                if proc.stderr:
                    while True:
                        chunk = await proc.stderr.read(4096)
                        if not chunk:
                            break
                        stderr_chunks.append(chunk)

            stderr_task = asyncio.create_task(_drain_stderr())

            streamed_any = False
            accumulated_deltas: list[str] = []
            final_response: str | None = None
            captured_conv_id: str | None = active_conv_id
            captured_perm_mode: str | None = None
            cli_status: str | None = None
            result_received = False
            denied_actions: list[dict[str, Any]] = []
            captured_usage: dict[str, int] | None = None

            # Read stdout line by line and parse NDJSON events
            if proc.stdout:
                while True:
                    line = await proc.stdout.readline()
                    if not line:
                        break
                    line_str = line.decode("utf-8", errors="replace").strip()
                    if not line_str:
                        continue

                    try:
                        data = json.loads(line_str)
                    except json.JSONDecodeError:
                        logger.debug("Non-JSON stdout line from agy: %s", line_str)
                        continue

                    event = data.get("event")

                    if event == "init":
                        init_conv = data.get("conversation_id") or data.get("init", {}).get("conversation_id")
                        if init_conv:
                            captured_conv_id = init_conv
                            self.set_conversation_id(init_conv, workspace)

                        cli_perm = data.get("init", {}).get("permission_mode")
                        if cli_perm:
                            captured_perm_mode = cli_perm

                    elif event == "step_update":
                        step_update = data.get("step_update", {})
                        step_conv = step_update.get("conversation_id")
                        if step_conv:
                            captured_conv_id = step_conv
                            self.set_conversation_id(step_conv, workspace)

                        step_type = step_update.get("step_type")
                        if step_type == "agent_response":
                            delta = step_update.get("text_delta", "")
                            if delta:
                                streamed_any = True
                                accumulated_deltas.append(delta)
                                if on_delta:
                                    try:
                                        await on_delta(delta, captured_conv_id or "")
                                    except Exception as exc:
                                        logger.warning("Error in on_delta callback: %s", exc)

                        step_usage = step_update.get("usage")
                        if step_usage and isinstance(step_usage, dict):
                            captured_usage = {
                                "input_tokens": int(step_usage.get("input_tokens") or 0),
                                "output_tokens": int(step_usage.get("output_tokens") or 0),
                                "thinking_tokens": int(step_usage.get("thinking_tokens") or 0),
                                "cache_read_tokens": int(step_usage.get("cache_read_tokens") or 0),
                                "total_tokens": int(step_usage.get("total_tokens") or 0),
                            }
                            if on_usage:
                                try:
                                    await on_usage(captured_usage, captured_conv_id or "")
                                except Exception as exc:
                                    logger.warning("Error in on_usage callback: %s", exc)

                    elif event == "result":
                        result_received = True
                        res = data.get("result", {})
                        res_conv = res.get("conversation_id")
                        if res_conv:
                            captured_conv_id = res_conv
                            self.set_conversation_id(res_conv, workspace)
                        cli_status = res.get("status")
                        final_response = res.get("response")
                        denied_actions = res.get("denied_actions", [])

                        res_usage = res.get("usage")
                        if res_usage and isinstance(res_usage, dict):
                            captured_usage = {
                                "input_tokens": int(res_usage.get("input_tokens") or 0),
                                "output_tokens": int(res_usage.get("output_tokens") or 0),
                                "thinking_tokens": int(res_usage.get("thinking_tokens") or 0),
                                "cache_read_tokens": int(res_usage.get("cache_read_tokens") or 0),
                                "total_tokens": int(res_usage.get("total_tokens") or 0),
                            }
                            if on_usage:
                                try:
                                    await on_usage(captured_usage, captured_conv_id or "")
                                except Exception as exc:
                                    logger.warning("Error in on_usage callback: %s", exc)

            await proc.wait()
            await stderr_task
            stderr_text = b"".join(stderr_chunks).decode("utf-8", errors="replace").strip()

            if final_response is None and accumulated_deltas:
                final_response = "".join(accumulated_deltas)

            # A permission warning must not be treated as a successful task completion
            has_denials = bool(denied_actions)
            is_success = (proc.returncode == 0) and (cli_status != "FAILURE") and not has_denials

            effective_mode = captured_perm_mode or ("always-proceed" if norm_mode in ("full-auto", "full_auto", "auto") else "request-review")

            if not is_success:
                if has_denials:
                    denied_names = ", ".join(d.get("display_name", d.get("action", "action")) for d in denied_actions)
                    err_msg = (
                        f"Action requires permission review: {denied_names}. "
                        "In Review mode, actions requiring interactive approval are halted. "
                        "Switch to Full Auto mode to allow automatic execution without prompts."
                    )
                else:
                    err_msg = stderr_text or final_response or f"Antigravity CLI failed with exit code {proc.returncode}"

                return AdapterResult(
                    success=False,
                    operation="send_prompt",
                    message=err_msg,
                    data={
                        "conversation_id": captured_conv_id or "",
                        "streamed": streamed_any,
                        "exit_code": proc.returncode,
                        "denied_actions": denied_actions,
                        "usage": captured_usage,
                        "effective_permission_mode": effective_mode,
                        "requested_permission_mode": norm_mode,
                    },
                )

            return AdapterResult(
                success=True,
                operation="send_prompt",
                message=final_response or "Task completed",
                data={
                    "conversation_id": captured_conv_id or "",
                    "streamed": streamed_any,
                    "response": final_response or "",
                    "integration": self._integration_type,
                    "workspace": workspace,
                    "denied_actions": denied_actions,
                    "usage": captured_usage,
                    "effective_permission_mode": effective_mode,
                    "requested_permission_mode": norm_mode,
                },
            )

        except Exception as exc:
            logger.exception("Failed to execute Antigravity CLI: %s", exc)
            return AdapterResult(
                success=False,
                operation="send_prompt",
                message=f"Failed to execute Antigravity CLI: {exc}",
                data={"conversation_id": active_conv_id or ""},
            )

    async def get_status(self) -> AdapterResult:
        """Report integration status."""
        caps = self.get_capabilities()
        return AdapterResult(
            success=True,
            operation="get_status",
            message=(
                f"Integration: {'configured (' + (self._integration_type or '') + ')' if self._configured else 'NOT CONFIGURED (stub)'}"
            ),
            data={
                "configured": self._configured,
                "integration_type": self._integration_type,
                "binary_path": self._binary_path,
                "active_conversation_id": self._last_conversation_id,
                "capabilities": [
                    {"name": c.name, "supported": c.supported, "description": c.description}
                    for c in caps
                ],
            },
        )
