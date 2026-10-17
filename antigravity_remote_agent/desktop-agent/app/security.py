"""Security utilities — path traversal prevention, input validation, audit logging."""

from __future__ import annotations

import datetime
import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


# ── Path safety ──────────────────────────────────────────────────────────────


def is_path_safe(requested: str | Path, allowed_roots: list[Path]) -> bool:
    """Check that *requested* resolves inside one of the *allowed_roots*.

    Guards against:
    - Relative path traversal (``../../etc/passwd``)
    - Symlink escapes
    - Absolute paths outside configured roots
    """
    try:
        resolved = Path(requested).resolve(strict=False)
    except (OSError, ValueError):
        return False

    for root in allowed_roots:
        root_resolved = root.resolve()
        try:
            resolved.relative_to(root_resolved)
            return True
        except ValueError:
            continue

    return False


def sanitise_path(requested: str | Path, allowed_roots: list[Path]) -> Path | None:
    """Return the resolved path if safe, or ``None`` otherwise."""
    if is_path_safe(requested, allowed_roots):
        return Path(requested).resolve()
    return None


# ── Command policy ───────────────────────────────────────────────────────────

# Commands that are ALWAYS blocked regardless of allowlist.
_BLOCKED_PATTERNS = frozenset(
    {
        "rm -rf",
        "del /s",
        "format",
        "powershell",
        "cmd.exe",
        "reg delete",
        "net user",
        "netsh",
        "runas",
        "takeown",
        "icacls",
        "schtasks",
        "wmic",
    }
)


def validate_command(
    command_line: str,
    allowed_commands: list[str],
) -> tuple[bool, str]:
    """Validate a command against policy.

    Returns:
        (is_allowed, reason)
    """
    normalized = command_line.strip()

    if not normalized:
        return False, "Empty command"

    # Check blocklist first
    lower = normalized.lower()
    for blocked in _BLOCKED_PATTERNS:
        if blocked in lower:
            return False, f"Command matches blocked pattern: {blocked}"

    # Check allowlist
    if not any(normalized == allowed.strip() for allowed in allowed_commands):
        return False, f"Command not in allowlist: {normalized}"

    return True, "OK"


# ── Input validation ─────────────────────────────────────────────────────────


def validate_request_id(request_id: str) -> bool:
    """Validate that a request ID is a reasonable identifier."""
    if not request_id or len(request_id) > 256:
        return False
    # Allow alphanumeric, hyphens, underscores
    return all(c.isalnum() or c in "-_" for c in request_id)


def validate_workspace_id(workspace_id: str, allowed_roots: list[Path]) -> Path | None:
    """Validate a workspace_id against allowed root paths.

    The requested workspace directory must exist, be a directory, and match
    one of the configured allowed roots.
    """
    if not workspace_id:
        return None

    try:
        requested = Path(workspace_id).resolve()
    except (OSError, ValueError):
        return None

    if not requested.exists() or not requested.is_dir():
        return None

    for root in allowed_roots:
        if requested == root.resolve():
            return requested

    return None


# ── Permission mode validation ───────────────────────────────────────────────

VALID_PERMISSION_MODES = frozenset({"review", "request-review", "edit", "accept-edits", "full-auto"})


def validate_permission_mode(mode: str | None) -> str | None:
    """Validate and normalize a permission mode string.

    Returns:
        'request-review' for Review mode
        'accept-edits' for Edit mode
        'full-auto' for Full Auto mode
        None if the mode is invalid or unsupported.
    """
    if not mode or not isinstance(mode, str):
        return "request-review"

    clean = mode.strip().lower()
    if clean in ("review", "request-review"):
        return "request-review"
    if clean in ("edit", "accept-edits"):
        return "accept-edits"
    if clean in ("full-auto", "full_auto"):
        return "full-auto"
    return None


# ── Audit logging ────────────────────────────────────────────────────────────

_AUDIT_FILE: str | None = None


def configure_audit_log(path: str) -> None:
    """Set the audit log file path."""
    global _AUDIT_FILE  # noqa: PLW0603
    _AUDIT_FILE = path


def audit(
    *,
    user: str = "unknown",
    device: str = "unknown",
    action: str,
    outcome: str,
    details: dict[str, Any] | None = None,
) -> None:
    """Write a minimal audit record.

    Records: timestamp, user/device, action, outcome.
    Does NOT record secrets or full prompt contents.
    """
    record: dict[str, Any] = {
        "ts": datetime.datetime.now(tz=datetime.timezone.utc).isoformat(),
        "user": user,
        "device": device,
        "action": action,
        "outcome": outcome,
    }
    if details:
        # Strip any keys that look like secrets
        safe_details = {
            k: v
            for k, v in details.items()
            if not any(s in k.lower() for s in ("secret", "token", "password", "key", "credential"))
        }
        if safe_details:
            record["details"] = safe_details

    line = json.dumps(record, default=str)
    logger.info("AUDIT: %s", line)

    if _AUDIT_FILE:
        try:
            with open(_AUDIT_FILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError as exc:
            logger.warning("Could not write audit record: %s", exc)
