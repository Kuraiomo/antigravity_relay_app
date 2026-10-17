"""Tests for relay module — protocol validation, reconnect, and mock mode."""

from __future__ import annotations

import pytest

from app.relay import (
    MSG_TASK_SUBMIT,
    MockRelayClient,
    _make_event_message,
    _make_register_message,
    _validate_message,
)


class TestProtocolMessages:
    def test_register_message(self) -> None:
        msg = _make_register_message("device-123", "0.1.0")
        assert msg["type"] == "agent.register"
        assert msg["protocol_version"] == 1
        assert msg["device_id"] == "device-123"

    def test_event_message(self) -> None:
        msg = _make_event_message("req-1", "task-1", "running", {"message": "Started"})
        assert msg["type"] == "task.event"
        assert msg["request_id"] == "req-1"
        assert msg["event"] == "running"


class TestMessageValidation:
    def test_valid_task_submit(self) -> None:
        msg = {
            "type": MSG_TASK_SUBMIT,
            "request_id": "req-1",
            "task_id": "task-1",
            "operation": "antigravity.prompt",
        }
        is_valid, reason = _validate_message(msg)
        assert is_valid is True

    def test_missing_type(self) -> None:
        is_valid, reason = _validate_message({"request_id": "req-1"})
        assert is_valid is False
        assert "type" in reason.lower()

    def test_missing_request_id(self) -> None:
        msg = {"type": MSG_TASK_SUBMIT, "task_id": "task-1", "operation": "test"}
        is_valid, reason = _validate_message(msg)
        assert is_valid is False
        assert "request_id" in reason

    def test_missing_operation(self) -> None:
        msg = {"type": MSG_TASK_SUBMIT, "request_id": "req-1", "task_id": "task-1"}
        is_valid, reason = _validate_message(msg)
        assert is_valid is False

    def test_non_task_message_passes(self) -> None:
        # Non-task messages just need a valid type
        is_valid, _ = _validate_message({"type": "heartbeat.ack"})
        assert is_valid is True


class TestMockRelay:
    @pytest.mark.asyncio
    async def test_mock_inject_task(self) -> None:
        received: list[dict] = []

        async def handler(msg: dict) -> None:
            received.append(msg)

        client = MockRelayClient(
            url="wss://test.example.com/agent/ws",
            device_id="test-device",
            agent_version="0.1.0",
        )
        client.set_task_handler(handler)

        await client.inject_mock_task(
            operation="test.op",
            workspace_id="ws-1",
            prompt="Test prompt",
        )

        # Allow asyncio task to run
        import asyncio
        await asyncio.sleep(0.1)

        assert len(received) == 1
        assert received[0]["operation"] == "test.op"
        assert received[0]["payload"]["prompt"] == "Test prompt"
