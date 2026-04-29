"""Progress reporting for codex-flow workflows."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal, TextIO

PROGRESS_MARKER = "codex-flow.progress.v1"
PROGRESS_MODES = ("plain", "json", "quiet")

ProgressMode = Literal["plain", "json", "quiet"]
Workflow = Literal["implement", "review"]


@dataclass(frozen=True)
class ProgressConfig:
    """Runtime configuration for progress output and persisted normalized logs."""

    mode: ProgressMode = "quiet"
    log_enabled: bool = False
    state_home: Path | None = None
    stream: TextIO | None = None


class ProgressReporter:
    """Emit normalized progress events to stderr and an external state log."""

    def __init__(
        self,
        workflow: Workflow,
        repository: Path,
        config: ProgressConfig | None = None,
    ) -> None:
        self.workflow = workflow
        self.repository = repository.resolve()
        self.config = config or ProgressConfig()
        self.run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
        self.state_home = resolve_state_home(self.config.state_home)
        self.log_path = (
            repository_state_dir(self.repository, self.state_home) / f"{self.run_id}.jsonl"
            if self.config.log_enabled
            else None
        )
        self._stream = self.config.stream or sys.stderr

        if self.config.mode not in PROGRESS_MODES:
            raise ValueError(f"Unsupported progress mode: {self.config.mode}")

    def emit(self, phase: str, status: str, message: str, **details: Any) -> dict[str, Any]:
        """Emit one normalized progress event."""
        event: dict[str, Any] = {
            "marker": PROGRESS_MARKER,
            "ts": _timestamp(),
            "run_id": self.run_id,
            "workflow": self.workflow,
            "phase": phase,
            "status": status,
            "message": message,
        }
        event.update({key: value for key, value in details.items() if value is not None})
        self._write_log(event)
        self._write_stream(event)
        return event

    def _write_log(self, event: dict[str, Any]) -> None:
        if self.log_path is None:
            return
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        with self.log_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, sort_keys=True) + "\n")

    def _write_stream(self, event: dict[str, Any]) -> None:
        if self.config.mode == "quiet":
            return
        if self.config.mode == "json":
            print(json.dumps(event, sort_keys=True), file=self._stream)
            return
        print(f"codex-flow: {event['message']}", file=self._stream)


def resolve_state_home(override: Path | None = None) -> Path:
    """Return the external codex-flow state directory root."""
    if override is not None:
        return override
    xdg_state_home = os.environ.get("XDG_STATE_HOME")
    if xdg_state_home:
        return Path(xdg_state_home) / "codex-flow"
    return Path.home() / ".local" / "state" / "codex-flow"


def repository_state_dir(repository: Path, state_home: Path | None = None) -> Path:
    """Return the external state directory for one repository."""
    return (state_home or resolve_state_home()) / "runs" / repository_state_key(repository)


def repository_state_key(repository: Path) -> str:
    """Return a stable, non-reversible key for a repository path."""
    digest = hashlib.sha256(str(repository.resolve()).encode("utf-8")).hexdigest()
    return digest[:16]


def _timestamp() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")
