"""Structured request and response contracts for codex-flow."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ImplementationRequest:
    """Validated implementation request."""

    request_path: Path
    repository: Path
    requirements: list[str]
    constraints: list[str]
    verification: str
    context_files: list[str]
    raw_markdown: str

    @property
    def output_path(self) -> Path:
        """Return the standardized implementation output path."""
        return self.request_path.with_name(f"{self.request_path.stem}.implementation-output.md")


@dataclass(frozen=True)
class ReviewRequest:
    """Validated review request."""

    request_path: Path
    repository: Path
    branch: str | None
    review_scope: str
    output_file: str
    date: str | None
    requirements: list[str]
    constraints: list[str]
    evidence: str
    review_focus: list[str]
    raw_markdown: str

    @property
    def output_path(self) -> Path:
        """Resolve the requested review output path under the repository."""
        candidate = (self.repository / self.output_file).resolve()
        repo_root = self.repository.resolve()
        try:
            candidate.relative_to(repo_root)
        except ValueError as err:
            raise ValueError(
                f"Output File must resolve under repository: {self.output_file}"
            ) from err
        return candidate
