"""Configuration loading and validation.

Reads from environment variables (with optional .env file support).
All required values are validated at startup; missing values cause a
clear error rather than a silent misconfiguration.
"""

from __future__ import annotations

import logging
import platform
import uuid
from pathlib import Path

from dotenv import load_dotenv
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings

logger = logging.getLogger(__name__)


def _default_device_id() -> str:
    """Generate a stable device ID from hostname + a persisted UUID."""
    id_file = Path.home() / ".antigravity_agent_device_id"
    if id_file.exists():
        return id_file.read_text().strip()
    new_id = f"{platform.node()}-{uuid.uuid4().hex[:12]}"
    try:
        id_file.write_text(new_id)
        logger.info("Generated new device ID and saved to %s", id_file)
    except OSError:
        logger.warning("Could not persist device ID to %s", id_file)
    return new_id


class AgentConfig(BaseSettings):
    """Validated agent configuration."""

    # ── Connection ───────────────────────────────────────
    relay_url: str = Field(
        default="wss://remote.example.com/agent/ws",
        description="Relay server WebSocket URL",
    )
    enrollment_token: str = Field(
        default="",
        description="One-time enrollment token from relay admin",
    )
    device_id: str = Field(
        default="",
        description="Stable device identifier (auto-generated if blank)",
    )
    agent_secret: str = Field(
        default="",
        description="Short-lived access token (auto-refreshed after enrollment)",
    )

    # ── Workspaces ───────────────────────────────────────
    workspace_roots: list[str] | str = Field(
        default_factory=list,
        description="Comma-separated absolute paths the agent may access",
    )

    # ── Commands ─────────────────────────────────────────
    allowed_commands: list[str] | str = Field(
        default_factory=lambda: ["git status", "pytest", "ruff check"],
        description="Comma-separated allowed commands",
    )
    command_timeout: int = Field(default=60, ge=1, le=600)
    max_output_size: int = Field(default=524_288, ge=1024)

    # ── Files ────────────────────────────────────────────
    max_file_size: int = Field(default=1_048_576, ge=1024)

    # ── Logging ──────────────────────────────────────────
    log_file: str = Field(default="agent.log")
    log_level: str = Field(default="INFO")

    # ── Heartbeat / reconnect ────────────────────────────
    heartbeat_interval: int = Field(default=30, ge=5, le=300)

    # ── Behaviour ────────────────────────────────────────
    auto_start: bool = Field(default=False)
    mock_mode: bool = Field(default=False)

    # ── Validators ───────────────────────────────────────
    @field_validator("workspace_roots", mode="after")
    @classmethod
    def _parse_workspace_roots(cls, v: object) -> list[str]:
        if isinstance(v, str):
            return [p.strip() for p in v.split(",") if p.strip()]
        if isinstance(v, list):
            return [str(p).strip() for p in v if str(p).strip()]
        return []

    @field_validator("allowed_commands", mode="after")
    @classmethod
    def _parse_allowed_commands(cls, v: object) -> list[str]:
        if isinstance(v, str):
            return [c.strip() for c in v.split(",") if c.strip()]
        if isinstance(v, list):
            return [str(c).strip() for c in v if str(c).strip()]
        return []

    @field_validator("log_level")
    @classmethod
    def _validate_log_level(cls, v: str) -> str:
        v = v.upper()
        if v not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
            raise ValueError(f"Invalid log level: {v}")
        return v

    model_config = {"env_prefix": "", "env_file": ".env", "extra": "ignore"}

    # ── Post-init ────────────────────────────────────────
    def model_post_init(self, __context: object) -> None:
        if not self.device_id:
            self.device_id = _default_device_id()

    # ── Helpers ──────────────────────────────────────────
    def resolved_workspace_roots(self) -> list[Path]:
        """Return validated, resolved workspace root paths."""
        roots: list[Path] = []
        for raw in self.workspace_roots:
            p = Path(raw).resolve()
            if p.is_dir():
                roots.append(p)
            else:
                logger.warning("Workspace root does not exist or is not a directory: %s", p)
        return roots

    def is_command_allowed(self, command_line: str) -> bool:
        """Check whether a command string is in the allowlist."""
        normalized = command_line.strip()
        return any(normalized == allowed.strip() for allowed in self.allowed_commands)


def load_config(env_file: str | None = None) -> AgentConfig:
    """Load and validate agent configuration.

    Args:
        env_file: Path to a .env file.  Falls back to .env in cwd.

    Returns:
        Fully validated AgentConfig.

    Raises:
        pydantic.ValidationError: If required values are missing or invalid.
    """
    if env_file:
        load_dotenv(env_file)
    elif Path(".env").exists():
        load_dotenv(".env")

    config = AgentConfig()

    # Log configuration summary (never log secrets)
    logger.info("Configuration loaded:")
    logger.info("  relay_url    = %s", config.relay_url)
    logger.info("  device_id    = %s", config.device_id)
    logger.info("  workspaces   = %s", config.workspace_roots)
    logger.info("  mock_mode    = %s", config.mock_mode)
    logger.info("  allowed_cmds = %s", config.allowed_commands)

    return config
