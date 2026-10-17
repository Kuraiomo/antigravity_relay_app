"""Tests for workspace module — file listing and reading safety."""

from __future__ import annotations

from pathlib import Path

import pytest

from app.workspace import list_files, read_file


@pytest.fixture
def workspace(tmp_path: Path) -> Path:
    """Create a populated workspace."""
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "main.py").write_text("print('hello world')")
    (tmp_path / "src" / "utils.py").write_text("def helper(): pass")
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "readme.md").write_text("# Project\n\nDescription here.")
    (tmp_path / ".hidden").mkdir()
    (tmp_path / ".hidden" / "secret.txt").write_text("should be hidden")
    return tmp_path


class TestListFiles:
    def test_list_root(self, workspace: Path) -> None:
        result = list_files(workspace, "", [workspace])
        assert "entries" in result
        names = [e["name"] for e in result["entries"]]
        assert "src" in names
        assert "docs" in names
        # Hidden dirs should be filtered
        assert ".hidden" not in names

    def test_list_subdirectory(self, workspace: Path) -> None:
        result = list_files(workspace, "src", [workspace])
        assert "entries" in result
        names = [e["name"] for e in result["entries"]]
        assert "main.py" in names
        assert "utils.py" in names

    def test_list_outside_root(self, workspace: Path) -> None:
        result = list_files(workspace, "../../..", [workspace])
        assert "error" in result

    def test_list_nonexistent(self, workspace: Path) -> None:
        result = list_files(workspace, "nonexistent", [workspace])
        assert "error" in result

    def test_truncation(self, workspace: Path) -> None:
        result = list_files(workspace, "src", [workspace], max_entries=1)
        assert result.get("truncated") is True
        assert len(result["entries"]) == 1


class TestReadFile:
    def test_read_valid_file(self, workspace: Path) -> None:
        result = read_file(workspace, "src/main.py", [workspace])
        assert "content" in result
        assert "hello world" in result["content"]

    def test_read_outside_root(self, workspace: Path) -> None:
        result = read_file(workspace, "../../../etc/passwd", [workspace])
        assert "error" in result

    def test_read_nonexistent(self, workspace: Path) -> None:
        result = read_file(workspace, "nonexistent.py", [workspace])
        assert "error" in result

    def test_read_oversized_file(self, workspace: Path) -> None:
        big = workspace / "big.bin"
        big.write_bytes(b"x" * 2_000_000)
        result = read_file(workspace, "big.bin", [workspace], max_size=1_000_000)
        assert "error" in result
        assert "too large" in result["error"].lower()

    def test_read_directory(self, workspace: Path) -> None:
        result = read_file(workspace, "src", [workspace])
        assert "error" in result
