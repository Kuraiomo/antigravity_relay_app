"""Command execution — restricted to allowlisted commands with sandboxing."""

from __future__ import annotations

import asyncio
import logging
import shlex
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

from app.security import audit, validate_command

logger = logging.getLogger(__name__)


async def execute_command(
    command_line: str,
    working_directory: Path,
    allowed_commands: list[str],
    allowed_roots: list[Path],
    timeout: int = 60,
    max_output: int = 524_288,
    device_id: str = "unknown",
    user: str = "unknown",
) -> AsyncIterator[dict[str, Any]]:
    """Execute a command and yield status events.

    This generator yields dictionaries with event types:
    - ``accepted``: Command has been validated and will run.
    - ``running``: Command is executing.
    - ``stdout``: Partial standard output.
    - ``stderr``: Partial standard error.
    - ``completed``: Command finished successfully.
    - ``failed``: Command failed or was denied.

    Security constraints:
    - Command must be in the allowlist.
    - Working directory must be within allowed roots.
    - ``shell=True`` is **never** used.
    - Output is capped at ``max_output`` bytes.
    - A timeout is enforced.
    """
    # ── Policy check ────────────────────────────────────
    is_allowed, reason = validate_command(command_line, allowed_commands)
    if not is_allowed:
        audit(
            user=user,
            device=device_id,
            action=f"command.denied:{command_line}",
            outcome="denied",
            details={"reason": reason},
        )
        yield {"event": "failed", "message": f"Command denied: {reason}"}
        return

    # Validate working directory
    wd = working_directory.resolve()
    in_root = any(
        wd == root.resolve() or str(wd).startswith(str(root.resolve()) + "\\")
        or str(wd).startswith(str(root.resolve()) + "/")
        for root in allowed_roots
    )
    if not in_root:
        yield {"event": "failed", "message": "Working directory is outside allowed roots"}
        return

    # ── Parse command into argument array ───────────────
    try:
        args = shlex.split(command_line)
    except ValueError as exc:
        yield {"event": "failed", "message": f"Cannot parse command: {exc}"}
        return

    audit(
        user=user,
        device=device_id,
        action=f"command.execute:{command_line}",
        outcome="accepted",
    )
    yield {"event": "accepted", "message": f"Executing: {command_line}"}

    # ── Execute ─────────────────────────────────────────
    total_output = 0
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(wd),
            # Never use shell=True
        )

        yield {"event": "running", "message": "Process started", "pid": proc.pid}

        # Stream output
        async def _read_stream(
            stream: asyncio.StreamReader | None,
            stream_name: str,
        ) -> list[dict[str, Any]]:
            events: list[dict[str, Any]] = []
            nonlocal total_output
            if stream is None:
                return events
            while True:
                line = await stream.readline()
                if not line:
                    break
                total_output += len(line)
                if total_output > max_output:
                    events.append({
                        "event": stream_name,
                        "data": "[output truncated — size limit reached]",
                    })
                    break
                try:
                    text = line.decode("utf-8", errors="replace").rstrip("\n\r")
                except Exception:
                    text = "[binary data]"
                events.append({"event": stream_name, "data": text})
            return events

        # Wait for both streams concurrently
        stdout_task = asyncio.create_task(_read_stream(proc.stdout, "stdout"))
        stderr_task = asyncio.create_task(_read_stream(proc.stderr, "stderr"))

        try:
            await asyncio.wait_for(proc.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            audit(
                user=user,
                device=device_id,
                action=f"command.timeout:{command_line}",
                outcome="failed",
            )
            yield {"event": "failed", "message": f"Command timed out after {timeout}s"}
            return

        stdout_events = await stdout_task
        stderr_events = await stderr_task

        for event in stdout_events:
            yield event
        for event in stderr_events:
            yield event

        exit_code = proc.returncode
        if exit_code == 0:
            audit(
                user=user,
                device=device_id,
                action=f"command.completed:{command_line}",
                outcome="success",
            )
            yield {"event": "completed", "exit_code": exit_code, "message": "Command completed"}
        else:
            audit(
                user=user,
                device=device_id,
                action=f"command.failed:{command_line}",
                outcome="failed",
                details={"exit_code": exit_code},
            )
            yield {
                "event": "failed",
                "exit_code": exit_code,
                "message": f"Command exited with code {exit_code}",
            }

    except FileNotFoundError:
        yield {"event": "failed", "message": f"Command not found: {args[0]}"}
    except PermissionError:
        yield {"event": "failed", "message": "Permission denied"}
    except OSError as exc:
        yield {"event": "failed", "message": f"OS error: {exc}"}
