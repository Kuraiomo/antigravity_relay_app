"""Workspace operations — safe file listing and reading within configured roots."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from app.security import is_path_safe, sanitise_path

logger = logging.getLogger(__name__)


# ── File listing ─────────────────────────────────────────────────────────────


def list_files(
    workspace_root: Path,
    relative_path: str = "",
    allowed_roots: list[Path] | None = None,
    max_entries: int = 500,
) -> dict[str, Any]:
    """List files and directories within a workspace root.

    Args:
        workspace_root: The validated workspace root.
        relative_path: Subdirectory to list (relative to root).
        allowed_roots: All configured workspace roots for path validation.
        max_entries: Maximum number of entries to return.

    Returns:
        Dict with ``path``, ``entries``, and ``truncated`` keys.
    """
    roots = allowed_roots or [workspace_root]
    target = (workspace_root / relative_path).resolve()

    # Validate the resolved path is inside allowed roots
    if not is_path_safe(target, roots):
        return {"error": "Path is outside allowed workspace roots", "path": relative_path}

    if not target.is_dir():
        return {"error": "Not a directory", "path": relative_path}

    entries: list[dict[str, Any]] = []
    try:
        for i, entry in enumerate(sorted(target.iterdir())):
            if i >= max_entries:
                return {
                    "path": relative_path or ".",
                    "entries": entries,
                    "truncated": True,
                }

            # Skip hidden files/dirs (starting with .)
            if entry.name.startswith("."):
                continue

            # Validate each entry stays within allowed roots
            try:
                resolved_entry = entry.resolve()
            except OSError:
                continue

            if not is_path_safe(resolved_entry, roots):
                continue

            entry_info: dict[str, Any] = {
                "name": entry.name,
                "is_dir": entry.is_dir(),
            }
            if entry.is_file():
                try:
                    entry_info["size"] = entry.stat().st_size
                except OSError:
                    entry_info["size"] = None

            entries.append(entry_info)

    except PermissionError:
        return {"error": "Permission denied", "path": relative_path}
    except OSError as exc:
        return {"error": f"OS error: {exc}", "path": relative_path}

    return {
        "path": relative_path or ".",
        "entries": entries,
        "truncated": False,
    }


# ── File reading ─────────────────────────────────────────────────────────────


def read_file(
    workspace_root: Path,
    relative_path: str,
    allowed_roots: list[Path] | None = None,
    max_size: int = 1_048_576,
) -> dict[str, Any]:
    """Read the contents of a text file within a workspace.

    Args:
        workspace_root: The validated workspace root.
        relative_path: File path relative to the root.
        allowed_roots: All configured workspace roots for path validation.
        max_size: Maximum file size in bytes.

    Returns:
        Dict with ``path``, ``content``, ``size``, and ``truncated`` keys,
        or an ``error`` key on failure.
    """
    roots = allowed_roots or [workspace_root]
    target = sanitise_path(workspace_root / relative_path, roots)

    if target is None:
        return {"error": "Path is outside allowed workspace roots", "path": relative_path}

    if not target.is_file():
        return {"error": "Not a file", "path": relative_path}

    try:
        size = target.stat().st_size
    except OSError as exc:
        return {"error": f"Cannot stat file: {exc}", "path": relative_path}

    if size > max_size:
        return {
            "error": f"File too large ({size} bytes, limit {max_size})",
            "path": relative_path,
            "size": size,
        }

    try:
        content = target.read_text(encoding="utf-8", errors="replace")
    except PermissionError:
        return {"error": "Permission denied", "path": relative_path}
    except OSError as exc:
        return {"error": f"Read error: {exc}", "path": relative_path}

    return {
        "path": relative_path,
        "content": content,
        "size": size,
        "truncated": False,
    }
