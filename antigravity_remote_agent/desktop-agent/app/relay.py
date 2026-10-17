"""Relay connection — outbound WebSocket client with reconnect, heartbeat, and mock mode."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import random
from collections.abc import Callable, Coroutine
from typing import Any

logger = logging.getLogger(__name__)

# ── Protocol message types ───────────────────────────────────────────────────

MSG_AGENT_REGISTER = "agent.register"
MSG_AGENT_REGISTERED = "agent.registered"
MSG_HEARTBEAT = "heartbeat"
MSG_HEARTBEAT_ACK = "heartbeat.ack"
MSG_TASK_SUBMIT = "task.submit"
MSG_TASK_EVENT = "task.event"
MSG_ERROR = "error"


def _make_register_message(device_id: str, agent_version: str) -> dict[str, Any]:
    return {
        "type": MSG_AGENT_REGISTER,
        "protocol_version": 1,
        "device_id": device_id,
        "agent_version": agent_version,
    }


def _make_event_message(
    request_id: str,
    task_id: str,
    event: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    msg: dict[str, Any] = {
        "type": MSG_TASK_EVENT,
        "request_id": request_id,
        "task_id": task_id,
        "event": event,
    }
    if payload:
        msg["payload"] = payload
    return msg


def _validate_message(data: dict[str, Any]) -> tuple[bool, str]:
    """Basic schema validation for incoming messages."""
    msg_type = data.get("type")
    if not msg_type or not isinstance(msg_type, str):
        return False, "Missing or invalid 'type' field"

    if msg_type == MSG_TASK_SUBMIT:
        required = ["request_id", "operation"]
        for field in required:
            if field not in data:
                return False, f"Missing required field: {field}"
        if not isinstance(data.get("request_id"), str):
            return False, "request_id must be a string"

    return True, "OK"


# ── Relay client ─────────────────────────────────────────────────────────────

TaskHandler = Callable[[dict[str, Any]], Coroutine[Any, Any, None]]


class RelayClient:
    """Outbound WebSocket connection to the relay server.

    Features:
    - Exponential backoff with jitter on reconnect
    - Heartbeat keep-alive
    - Message validation on both send and receive
    - Mock mode for development
    """

    def __init__(
        self,
        url: str,
        device_id: str,
        agent_version: str,
        agent_secret: str = "",
        heartbeat_interval: int = 30,
        mock_mode: bool = False,
    ) -> None:
        self.url = url
        self.device_id = device_id
        self.agent_version = agent_version
        self.agent_secret = agent_secret
        self.heartbeat_interval = heartbeat_interval
        self.mock_mode = mock_mode

        self._ws: Any = None
        self._connected = False
        self._task_handler: TaskHandler | None = None
        self._reconnect_attempt = 0
        self._max_backoff = 120  # seconds
        self._running = False

    def set_task_handler(self, handler: TaskHandler) -> None:
        """Register the callback for incoming task messages."""
        self._task_handler = handler

    @property
    def is_connected(self) -> bool:
        return self._connected

    async def send_event(
        self,
        request_id: str,
        task_id: str,
        event: str,
        payload: dict[str, Any] | None = None,
    ) -> None:
        """Send a task event to the relay."""
        msg = _make_event_message(request_id, task_id, event, payload)
        await self._send(msg)

    async def _send(self, message: dict[str, Any]) -> None:
        """Serialize and send a message."""
        raw = json.dumps(message)
        if self.mock_mode:
            logger.debug("[MOCK] Would send: %s", raw[:500])
            return
        if self._ws is not None:
            try:
                await self._ws.send(raw)
                logger.info(
                    "Sent event: event=%s request_id=%s task_id=%s",
                    message.get("event"),
                    message.get("request_id"),
                    message.get("task_id"),
                )
            except Exception as exc:
                logger.error("Send failed: %s", exc)
                self._connected = False

    async def _on_message(self, raw: str | bytes) -> None:
        """Process an incoming raw message."""
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("Received non-JSON message")
            return

        is_valid, reason = _validate_message(data)
        if not is_valid:
            logger.warning("Invalid message: %s", reason)
            return

        msg_type = data.get("type")

        if msg_type == MSG_AGENT_REGISTERED:
            logger.info("Agent registered with relay")
            self._reconnect_attempt = 0

        elif msg_type == MSG_HEARTBEAT_ACK:
            logger.debug("Heartbeat acknowledged")

        elif msg_type == MSG_TASK_SUBMIT:
            if not data.get("task_id"):
                data["task_id"] = f"task-{data.get('request_id', 'unknown')}"
            logger.info(
                "Received task: request_id=%s task_id=%s operation=%s",
                data.get("request_id"),
                data.get("task_id"),
                data.get("operation"),
            )
            if self._task_handler:
                asyncio.create_task(self._task_handler(data))
            else:
                logger.warning("No task handler registered, ignoring task")

        elif msg_type == MSG_ERROR:
            logger.error("Relay error: %s", data.get("message", "unknown"))

        else:
            logger.debug("Unhandled message type: %s", msg_type)

    def _backoff_delay(self) -> float:
        """Exponential backoff with jitter."""
        base = float(min(2**self._reconnect_attempt, self._max_backoff))
        jitter = random.uniform(0, base * 0.3)
        return float(base + jitter)

    async def _heartbeat_loop(self) -> None:
        """Send periodic heartbeats."""
        while self._running and self._connected:
            await asyncio.sleep(self.heartbeat_interval)
            if self._connected:
                await self._send({"type": MSG_HEARTBEAT, "device_id": self.device_id})

    async def connect(self) -> None:
        """Connect to the relay with reconnect logic.

        In mock mode, simulates a successful connection.
        """
        self._running = True

        if self.mock_mode:
            logger.info("[MOCK MODE] Simulating relay connection to %s", self.url)
            self._connected = True
            await self._send(_make_register_message(self.device_id, self.agent_version))
            logger.info("[MOCK MODE] Agent registered (simulated)")

            # In mock mode, just keep running with heartbeats
            while self._running:
                await asyncio.sleep(self.heartbeat_interval)
                logger.debug("[MOCK] Heartbeat")
            return

        # Real connection loop
        import websockets

        while self._running:
            try:
                extra_headers = {}
                if self.agent_secret:
                    extra_headers["Authorization"] = f"Bearer {self.agent_secret}"

                async with websockets.connect(
                    self.url,
                    extra_headers=extra_headers if extra_headers else None,
                    ping_interval=self.heartbeat_interval,
                    ping_timeout=self.heartbeat_interval * 2,
                ) as ws:
                    self._ws = ws
                    self._connected = True
                    self._reconnect_attempt = 0

                    # Register
                    await self._send(
                        _make_register_message(self.device_id, self.agent_version)
                    )

                    logger.info("Connected to relay: %s", self.url)

                    # Start heartbeat
                    heartbeat_task = asyncio.create_task(self._heartbeat_loop())

                    try:
                        async for raw in ws:
                            await self._on_message(raw)
                    finally:
                        heartbeat_task.cancel()
                        self._connected = False
                        self._ws = None

            except Exception as exc:
                self._connected = False
                self._ws = None
                self._reconnect_attempt += 1
                delay = self._backoff_delay()
                logger.warning(
                    "Connection failed (attempt %d): %s — retrying in %.1fs",
                    self._reconnect_attempt,
                    exc,
                    delay,
                )
                await asyncio.sleep(delay)

    async def disconnect(self) -> None:
        """Gracefully disconnect."""
        self._running = False
        self._connected = False
        if self._ws is not None:
            with contextlib.suppress(Exception):
                await self._ws.close()
            self._ws = None
        logger.info("Disconnected from relay")


# ── Mock relay for development ───────────────────────────────────────────────


class MockRelayClient(RelayClient):
    """A relay client that simulates server responses for development.

    Periodically generates mock task submissions so the agent
    can be tested without a real relay server.
    """

    def __init__(self, **kwargs: Any) -> None:
        super().__init__(mock_mode=True, **kwargs)
        self._mock_task_counter = 0

    async def inject_mock_task(
        self,
        operation: str = "antigravity.prompt",
        workspace_id: str = "",
        prompt: str = "Mock task: describe the project structure",
    ) -> None:
        """Inject a simulated task for testing."""
        self._mock_task_counter += 1
        mock_msg = json.dumps(
            {
                "type": MSG_TASK_SUBMIT,
                "request_id": f"mock-req-{self._mock_task_counter}",
                "task_id": f"mock-task-{self._mock_task_counter}",
                "operation": operation,
                "workspace_id": workspace_id,
                "payload": {"prompt": prompt},
            }
        )
        await self._on_message(mock_msg)
