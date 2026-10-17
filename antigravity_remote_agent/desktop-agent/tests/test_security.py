"""Tests for security module — path traversal, command policy, input validation."""

from __future__ import annotations

from pathlib import Path

import pytest

from app.security import (
    is_path_safe,
    sanitise_path,
    validate_command,
    validate_request_id,
    validate_workspace_id,
)

# ── Fixtures ─────────────────────────────────────────────────────────────────


@pytest.fixture
def workspace(tmp_path: Path) -> Path:
    """Create a temporary workspace with some files."""
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "main.py").write_text("print('hello')")
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "readme.md").write_text("# Readme")
    return tmp_path


# ── Path safety tests ────────────────────────────────────────────────────────


class TestPathSafety:
    def test_path_inside_root(self, workspace: Path) -> None:
        assert is_path_safe(workspace / "src" / "main.py", [workspace]) is True

    def test_path_is_root(self, workspace: Path) -> None:
        assert is_path_safe(workspace, [workspace]) is True

    def test_path_outside_root(self, workspace: Path) -> None:
        assert is_path_safe(Path("/etc/passwd"), [workspace]) is False

    def test_relative_traversal(self, workspace: Path) -> None:
        malicious = workspace / "src" / ".." / ".." / ".." / "etc" / "passwd"
        assert is_path_safe(malicious, [workspace]) is False

    def test_absolute_path_outside(self, workspace: Path) -> None:
        assert is_path_safe(Path("C:\\Windows\\System32\\cmd.exe"), [workspace]) is False

    def test_multiple_roots(self, tmp_path: Path) -> None:
        root1 = tmp_path / "project_a"
        root2 = tmp_path / "project_b"
        root1.mkdir()
        root2.mkdir()
        (root1 / "file.txt").write_text("a")
        (root2 / "file.txt").write_text("b")
        assert is_path_safe(root1 / "file.txt", [root1, root2]) is True
        assert is_path_safe(root2 / "file.txt", [root1, root2]) is True

    def test_empty_roots(self, workspace: Path) -> None:
        assert is_path_safe(workspace / "src", []) is False

    def test_sanitise_safe_path(self, workspace: Path) -> None:
        result = sanitise_path(workspace / "src", [workspace])
        assert result is not None
        assert result.is_dir()

    def test_sanitise_unsafe_path(self, workspace: Path) -> None:
        result = sanitise_path(Path("/etc/shadow"), [workspace])
        assert result is None


# ── Command policy tests ─────────────────────────────────────────────────────


class TestCommandPolicy:
    ALLOWLIST = ["git status", "pytest", "ruff check"]

    def test_allowed_command(self) -> None:
        allowed, reason = validate_command("git status", self.ALLOWLIST)
        assert allowed is True

    def test_disallowed_command(self) -> None:
        allowed, reason = validate_command("rm -rf /", self.ALLOWLIST)
        assert allowed is False
        assert "blocked" in reason.lower() or "not in allowlist" in reason.lower()

    def test_blocked_powershell(self) -> None:
        allowed, reason = validate_command("powershell Get-Process", self.ALLOWLIST)
        assert allowed is False

    def test_blocked_cmd_exe(self) -> None:
        allowed, reason = validate_command("cmd.exe /c dir", self.ALLOWLIST)
        assert allowed is False

    def test_empty_command(self) -> None:
        allowed, reason = validate_command("", self.ALLOWLIST)
        assert allowed is False

    def test_command_not_in_allowlist(self) -> None:
        allowed, reason = validate_command("curl http://evil.com", self.ALLOWLIST)
        assert allowed is False

    def test_exact_match_required(self) -> None:
        # "git" alone should NOT match "git status"
        allowed, _ = validate_command("git", self.ALLOWLIST)
        assert allowed is False

    def test_command_with_extra_args(self) -> None:
        # "git status --short" should NOT match "git status"
        allowed, _ = validate_command("git status --short", self.ALLOWLIST)
        assert allowed is False


# ── Request ID validation ────────────────────────────────────────────────────


class TestRequestIdValidation:
    def test_valid_id(self) -> None:
        assert validate_request_id("abc-123_def") is True

    def test_empty_id(self) -> None:
        assert validate_request_id("") is False

    def test_too_long(self) -> None:
        assert validate_request_id("a" * 257) is False

    def test_special_chars(self) -> None:
        assert validate_request_id("id with spaces") is False
        assert validate_request_id("id;drop table") is False


# ── Workspace ID validation ──────────────────────────────────────────────────


class TestWorkspaceIdValidation:
    def test_valid_workspace(self, workspace: Path) -> None:
        result = validate_workspace_id(str(workspace), [workspace])
        assert result is not None
        assert result == workspace.resolve()

    def test_invalid_workspace(self, workspace: Path) -> None:
        result = validate_workspace_id("/nonexistent/path", [workspace])
        assert result is None

    def test_unauthorized_workspace(self, workspace: Path, tmp_path: Path) -> None:
        other = tmp_path / "other_project"
        other.mkdir()
        result = validate_workspace_id(str(other), [workspace])
        assert result is None
