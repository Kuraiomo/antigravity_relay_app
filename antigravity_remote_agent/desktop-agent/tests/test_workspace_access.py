"""Tests for workspace access, directory validation, and workspace roots handling."""

from __future__ import annotations

import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest

from app.adapters.antigravity import AntigravityAdapter
from app.config import AgentConfig
from app.main import TaskDispatcher
from app.relay import MockRelayClient
from app.security import validate_workspace_id


class TestWorkspaceValidationRules:
    def test_existing_configured_root(self, tmp_path: Path) -> None:
        root = tmp_path / "my_project"
        root.mkdir()
        assert validate_workspace_id(str(root), [root]) == root.resolve()

    def test_inaccessible_or_missing_directory(self, tmp_path: Path) -> None:
        missing = tmp_path / "does_not_exist"
        assert validate_workspace_id(str(missing), [tmp_path]) is None

    def test_file_instead_of_directory(self, tmp_path: Path) -> None:
        file_path = tmp_path / "file.txt"
        file_path.write_text("hello")
        assert validate_workspace_id(str(file_path), [tmp_path]) is None

    def test_unauthorized_directory_rejected(self, tmp_path: Path) -> None:
        allowed = tmp_path / "allowed"
        allowed.mkdir()
        unauthorized = tmp_path / "unauthorized"
        unauthorized.mkdir()
        assert validate_workspace_id(str(unauthorized), [allowed]) is None


class TestDispatcherWorkspaceEnforcement:
    @pytest.mark.asyncio
    async def test_rejects_inaccessible_workspace_before_cli(self, tmp_path: Path) -> None:
        allowed = tmp_path / "allowed"
        allowed.mkdir()

        config = AgentConfig(workspace_roots=[str(allowed)])
        relay = MockRelayClient(url="wss://mock", device_id="test-pc", agent_version="0.1.0")
        adapter = AntigravityAdapter()
        dispatcher = TaskDispatcher(config, relay, adapter)

        sent_events: list[dict] = []

        async def capture_event(req_id: str, task_id: str, event: str, payload: dict | None = None) -> None:
            sent_events.append({"event": event, "payload": payload})

        relay.send_event = capture_event  # type: ignore

        # Submit task with an invalid/unauthorized workspace
        await dispatcher.handle_task({
            "type": "task.submit",
            "request_id": "req-workspace-test-1",
            "task_id": "task-ws-1",
            "operation": "antigravity.prompt",
            "workspace_id": "C:\\fake\\nonexistent\\workspace",
            "payload": {"prompt": "List files"},
        })

        # Expected: accepted, then immediately failed with clear error message
        event_types = [e["event"] for e in sent_events]
        assert event_types == ["accepted", "failed"]
        assert "Workspace directory does not exist, is inaccessible, or is not in allowed roots" in sent_events[1]["payload"]["message"]

    @pytest.mark.asyncio
    async def test_workspace_roots_listing(self, tmp_path: Path) -> None:
        root1 = tmp_path / "project_alpha"
        root1.mkdir()
        sub1 = root1 / "sub_module"
        sub1.mkdir()

        config = AgentConfig(workspace_roots=[str(root1)])
        relay = MockRelayClient(url="wss://mock", device_id="test-pc", agent_version="0.1.0")
        adapter = AntigravityAdapter()
        dispatcher = TaskDispatcher(config, relay, adapter)

        sent_events: list[dict] = []

        async def capture_event(req_id: str, task_id: str, event: str, payload: dict | None = None) -> None:
            sent_events.append({"event": event, "payload": payload})

        relay.send_event = capture_event  # type: ignore

        await dispatcher.handle_task({
            "type": "task.submit",
            "request_id": "req-roots-test-1",
            "task_id": "task-roots-1",
            "operation": "workspace.roots",
            "payload": {},
        })

        assert len(sent_events) == 2
        assert sent_events[0]["event"] == "accepted"
        assert sent_events[1]["event"] == "completed"
        workspaces = sent_events[1]["payload"]["data"]["workspaces"]
        paths = [w["path"] for w in workspaces]
        assert str(root1.resolve()) in paths
        assert str(sub1.resolve()) in paths
