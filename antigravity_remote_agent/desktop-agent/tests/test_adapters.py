"""Tests for AntigravityAdapter — agy CLI integration, NDJSON stream parsing, conversation preservation."""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest

from app.adapters.antigravity import AntigravityAdapter, AdapterResult
from app.config import AgentConfig
from app.main import TaskDispatcher
from app.relay import MockRelayClient


@pytest.fixture
def mock_agy_cli(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Mock the official agy.exe CLI location."""
    fake_localappdata = tmp_path / "AppData" / "Local"
    fake_bin = fake_localappdata / "agy" / "bin"
    fake_bin.mkdir(parents=True)
    fake_exe = fake_bin / "agy.exe"
    fake_exe.write_text("echo fake agy")

    monkeypatch.setenv("LOCALAPPDATA", str(fake_localappdata))
    return fake_exe


class TestAdapterDetection:
    def test_detects_official_agy_cli(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()
        assert adapter._configured is True
        assert adapter._integration_type == "cli (agy)"
        assert adapter._binary_path == str(mock_agy_cli)


class TestAdapterStreamingAndConversation:
    @pytest.mark.asyncio
    async def test_stream_deltas_and_capture_conversation(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()

        ndjson_lines = [
            json.dumps({"event": "init", "conversation_id": "test-conv-456", "init": {"permission_mode": "request-review"}}),
            json.dumps({"event": "step_update", "step_update": {"conversation_id": "test-conv-456", "step_type": "user_input"}}),
            json.dumps({"event": "step_update", "step_update": {"conversation_id": "test-conv-456", "step_type": "agent_response", "text_delta": "Hello "}}),
            json.dumps({"event": "step_update", "step_update": {"conversation_id": "test-conv-456", "step_type": "agent_response", "text_delta": "world!"}}),
            json.dumps({"event": "result", "result": {"conversation_id": "test-conv-456", "status": "SUCCESS", "response": "Hello world!"}}),
        ]

        class FakeStreamReader:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [line.encode("utf-8") + b"\n" for line in lines]
                self._idx = 0

            async def readline(self) -> bytes:
                if self._idx < len(self._lines):
                    line = self._lines[self._idx]
                    self._idx += 1
                    return line
                return b""

            async def read(self, n: int = -1) -> bytes:
                return b""

        fake_proc = AsyncMock()
        fake_proc.stdout = FakeStreamReader(ndjson_lines)
        fake_proc.stderr = FakeStreamReader([])
        fake_proc.wait = AsyncMock(return_value=0)
        fake_proc.returncode = 0

        streamed_deltas: list[tuple[str, str]] = []

        async def on_delta(delta: str, conv_id: str) -> None:
            streamed_deltas.append((delta, conv_id))

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc) as mock_exec:
            result = await adapter.send_prompt("Hi", on_delta=on_delta)

            assert result.success is True
            assert result.message == "Hello world!"
            assert result.data["conversation_id"] == "test-conv-456"
            assert result.data["streamed"] is True

            # Check deltas streamed
            assert streamed_deltas == [("Hello ", "test-conv-456"), ("world!", "test-conv-456")]

            # Verify CLI arguments: --print, --output-format stream-json, --print-timeout 0
            mock_exec.assert_called_once()
            args = mock_exec.call_args[0]
            assert args[0] == str(mock_agy_cli)
            assert "--print" in args
            assert "--output-format" in args
            assert "stream-json" in args
            assert "--print-timeout" in args
            assert "0" in args
            assert "--dangerously-skip-permissions" not in args

        # Test follow-up conversation resume
        fake_proc2 = AsyncMock()
        fake_proc2.stdout = FakeStreamReader([
            json.dumps({"event": "result", "result": {"conversation_id": "test-conv-456", "status": "SUCCESS", "response": "Follow up"}}),
        ])
        fake_proc2.stderr = FakeStreamReader([])
        fake_proc2.wait = AsyncMock(return_value=0)
        fake_proc2.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc2) as mock_exec2:
            await adapter.send_prompt("Next question")
            args2 = mock_exec2.call_args[0]
            # Conversation ID was preserved and passed
            assert "--conversation" in args2
            conv_idx = args2.index("--conversation")
            assert args2[conv_idx + 1] == "test-conv-456"


class TestDispatcherPromptStreaming:
    @pytest.mark.asyncio
    async def test_dispatcher_emits_stdout_and_completed_without_duplicate(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()
        config = AgentConfig()
        relay = MockRelayClient(url="wss://mock", device_id="test-pc", agent_version="0.1.0")
        dispatcher = TaskDispatcher(config, relay, adapter)

        sent_events: list[dict[str, Any]] = []

        async def capture_event(req_id: str, task_id: str, event: str, payload: dict[str, Any] | None = None) -> None:
            sent_events.append({"request_id": req_id, "task_id": task_id, "event": event, "payload": payload})

        relay.send_event = capture_event  # type: ignore

        ndjson_lines = [
            json.dumps({"event": "init", "conversation_id": "conv-999"}),
            json.dumps({"event": "step_update", "step_update": {"conversation_id": "conv-999", "step_type": "agent_response", "text_delta": "Part 1 "}}),
            json.dumps({"event": "step_update", "step_update": {"conversation_id": "conv-999", "step_type": "agent_response", "text_delta": "Part 2"}}),
            json.dumps({"event": "result", "result": {"conversation_id": "conv-999", "status": "SUCCESS", "response": "Part 1 Part 2"}}),
        ]

        class FakeStreamReader:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [line.encode("utf-8") + b"\n" for line in lines]
                self._idx = 0

            async def readline(self) -> bytes:
                if self._idx < len(self._lines):
                    line = self._lines[self._idx]
                    self._idx += 1
                    return line
                return b""

            async def read(self, n: int = -1) -> bytes:
                return b""

        fake_proc = AsyncMock()
        fake_proc.stdout = FakeStreamReader(ndjson_lines)
        fake_proc.stderr = FakeStreamReader([])
        fake_proc.wait = AsyncMock(return_value=0)
        fake_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc):
            await dispatcher.handle_task({
                "type": "task.submit",
                "request_id": "11111111-1111-1111-1111-111111111111",
                "task_id": "task-test-1",
                "operation": "antigravity.prompt",
                "payload": {"prompt": "Write code"},
            })

        # Events emitted:
        # 1. accepted
        # 2. running
        # 3. stdout (Part 1)
        # 4. stdout (Part 2)
        # 5. completed (with message="Task completed", not repeating full text)
        event_types = [e["event"] for e in sent_events]
        assert event_types == ["accepted", "running", "stdout", "stdout", "completed"]

        # Check stdout payloads
        stdout_events = [e for e in sent_events if e["event"] == "stdout"]
        assert stdout_events[0]["payload"]["message"] == "Part 1 "
        assert stdout_events[0]["payload"]["conversation_id"] == "conv-999"
        assert stdout_events[1]["payload"]["message"] == "Part 2"
        assert stdout_events[1]["payload"]["conversation_id"] == "conv-999"

        # Check completed payload
        completed_event = [e for e in sent_events if e["event"] == "completed"][0]
        assert completed_event["payload"]["message"] == "Task completed"
        assert completed_event["payload"]["response"] == "Part 1 Part 2"
        assert completed_event["payload"]["conversation_id"] == "conv-999"

    @pytest.mark.asyncio
    async def test_adapter_parses_token_usage_and_emits_usage_events(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()
        config = AgentConfig()
        relay = MockRelayClient(url="wss://mock", device_id="test-pc", agent_version="0.1.0")
        dispatcher = TaskDispatcher(config, relay, adapter)

        sent_events: list[dict[str, Any]] = []

        async def capture_event(req_id: str, task_id: str, event: str, payload: dict[str, Any] | None = None) -> None:
            sent_events.append({"request_id": req_id, "task_id": task_id, "event": event, "payload": payload})

        relay.send_event = capture_event  # type: ignore

        cli_usage = {
            "input_tokens": 15684,
            "output_tokens": 57,
            "thinking_tokens": 45,
            "cache_read_tokens": 128,
            "total_tokens": 15741,
        }

        ndjson_lines = [
            json.dumps({"event": "init", "conversation_id": "conv-usage-1"}),
            json.dumps({
                "event": "step_update",
                "step_update": {
                    "conversation_id": "conv-usage-1",
                    "step_type": "agent_response",
                    "text_delta": "Response text",
                    "usage": cli_usage,
                },
            }),
            json.dumps({
                "event": "result",
                "result": {
                    "conversation_id": "conv-usage-1",
                    "status": "SUCCESS",
                    "response": "Response text",
                    "usage": cli_usage,
                },
            }),
        ]

        class FakeStreamReader:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [line.encode("utf-8") + b"\n" for line in lines]
                self._idx = 0

            async def readline(self) -> bytes:
                if self._idx < len(self._lines):
                    line = self._lines[self._idx]
                    self._idx += 1
                    return line
                return b""

            async def read(self, n: int = -1) -> bytes:
                return b""

        fake_proc = AsyncMock()
        fake_proc.stdout = FakeStreamReader(ndjson_lines)
        fake_proc.stderr = FakeStreamReader([])
        fake_proc.wait = AsyncMock(return_value=0)
        fake_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc):
            await dispatcher.handle_task({
                "type": "task.submit",
                "request_id": "22222222-2222-2222-2222-222222222222",
                "task_id": "task-usage-test",
                "operation": "antigravity.prompt",
                "payload": {"prompt": "Check tokens"},
            })

        # Verify usage event was emitted during stream
        usage_events = [e for e in sent_events if e["event"] == "usage"]
        assert len(usage_events) >= 1
        assert usage_events[0]["payload"]["usage"]["input_tokens"] == 15684
        assert usage_events[0]["payload"]["usage"]["output_tokens"] == 57
        assert usage_events[0]["payload"]["usage"]["total_tokens"] == 15741
        assert usage_events[0]["payload"]["usage"]["cache_read_tokens"] == 128

        # Verify completed event contains usage metadata
        completed_events = [e for e in sent_events if e["event"] == "completed"]
        assert len(completed_events) == 1
        assert "usage" in completed_events[0]["payload"]
        completed_usage = completed_events[0]["payload"]["usage"]
        assert completed_usage["input_tokens"] == 15684
        assert completed_usage["output_tokens"] == 57
        assert completed_usage["total_tokens"] == 15741


class TestPermissionModes:
    @pytest.mark.asyncio
    async def test_full_auto_passes_dangerously_skip_permissions(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()

        class FakeStreamReader:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [line.encode("utf-8") + b"\n" for line in lines]
                self._idx = 0

            async def readline(self) -> bytes:
                if self._idx < len(self._lines):
                    line = self._lines[self._idx]
                    self._idx += 1
                    return line
                return b""

            async def read(self, n: int = -1) -> bytes:
                return b""

        fake_proc = AsyncMock()
        fake_proc.stdout = FakeStreamReader([
            json.dumps({"event": "init", "conversation_id": "auto-conv", "init": {"permission_mode": "always-proceed"}}),
            json.dumps({"event": "result", "result": {"conversation_id": "auto-conv", "status": "SUCCESS", "response": "Executed automatically"}}),
        ])
        fake_proc.stderr = FakeStreamReader([])
        fake_proc.wait = AsyncMock(return_value=0)
        fake_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc) as mock_exec:
            res = await adapter.send_prompt("Test prompt", permission_mode="full-auto")
            assert res.success is True
            assert res.data["effective_permission_mode"] == "always-proceed"
            assert res.data["requested_permission_mode"] == "full-auto"

            args = mock_exec.call_args[0]
            assert "--dangerously-skip-permissions" in args

    @pytest.mark.asyncio
    async def test_edit_mode_passes_accept_edits(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()

        class FakeStreamReader:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [line.encode("utf-8") + b"\n" for line in lines]
                self._idx = 0

            async def readline(self) -> bytes:
                if self._idx < len(self._lines):
                    line = self._lines[self._idx]
                    self._idx += 1
                    return line
                return b""

            async def read(self, n: int = -1) -> bytes:
                return b""

        fake_proc = AsyncMock()
        fake_proc.stdout = FakeStreamReader([
            json.dumps({"event": "init", "conversation_id": "edit-conv", "init": {"permission_mode": "accept-edits"}}),
            json.dumps({"event": "result", "result": {"conversation_id": "edit-conv", "status": "SUCCESS", "response": "Edited files"}}),
        ])
        fake_proc.stderr = FakeStreamReader([])
        fake_proc.wait = AsyncMock(return_value=0)
        fake_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc) as mock_exec:
            res = await adapter.send_prompt("Edit files", permission_mode="accept-edits")
            assert res.success is True
            assert res.data["effective_permission_mode"] == "accept-edits"
            assert res.data["requested_permission_mode"] == "accept-edits"

            args = mock_exec.call_args[0]
            assert "--mode" in args
            mode_idx = args.index("--mode")
            assert args[mode_idx + 1] == "accept-edits"
            assert "--dangerously-skip-permissions" not in args

    @pytest.mark.asyncio
    async def test_denied_actions_in_review_mode_fails_task(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()

        class FakeStreamReader:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [line.encode("utf-8") + b"\n" for line in lines]
                self._idx = 0

            async def readline(self) -> bytes:
                if self._idx < len(self._lines):
                    line = self._lines[self._idx]
                    self._idx += 1
                    return line
                return b""

            async def read(self, n: int = -1) -> bytes:
                return b""

        fake_proc = AsyncMock()
        fake_proc.stdout = FakeStreamReader([
            json.dumps({"event": "init", "conversation_id": "review-denied", "init": {"permission_mode": "request-review"}}),
            json.dumps({
                "event": "result",
                "result": {
                    "conversation_id": "review-denied",
                    "status": "SUCCESS",
                    "denied_actions": [{"action": "terminal.execute", "display_name": "run_command: npm test"}],
                    "response": "Could not complete without approval",
                },
            }),
        ])
        fake_proc.stderr = FakeStreamReader([])
        fake_proc.wait = AsyncMock(return_value=0)
        fake_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=fake_proc):
            res = await adapter.send_prompt("Run npm test", permission_mode="request-review")
            # Permission warning must NOT be treated as a successful completion
            assert res.success is False
            assert "Action requires permission review" in res.message
            assert "Switch to Full Auto" in res.message

    @pytest.mark.asyncio
    async def test_dispatcher_rejects_invalid_permission_mode(self, mock_agy_cli: Path) -> None:
        adapter = AntigravityAdapter()
        config = AgentConfig()
        relay = MockRelayClient(url="wss://mock", device_id="test-pc", agent_version="0.1.0")
        dispatcher = TaskDispatcher(config, relay, adapter)

        sent_events: list[dict[str, Any]] = []

        async def capture_event(req_id: str, task_id: str, event: str, payload: dict[str, Any] | None = None) -> None:
            sent_events.append({"request_id": req_id, "task_id": task_id, "event": event, "payload": payload})

        relay.send_event = capture_event  # type: ignore

        await dispatcher.handle_task({
            "type": "task.submit",
            "request_id": "33333333-3333-3333-3333-333333333333",
            "task_id": "task-invalid-mode",
            "operation": "antigravity.prompt",
            "payload": {"prompt": "Run something", "permission_mode": "invalid-hacker-mode"},
        })

        failed_event = [e for e in sent_events if e["event"] == "failed"]
        assert len(failed_event) == 1
        assert "Unsupported or invalid permission mode" in failed_event[0]["payload"]["message"]
        assert failed_event[0]["payload"]["requested_permission_mode"] == "invalid-hacker-mode"
