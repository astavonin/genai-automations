"""Workflow execution for codex-flow."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any, cast

from .exceptions import ValidationError, WorkflowViolationError
from .markdown_parser import parse_implementation_request, parse_review_request
from .prompting import (
    build_implementation_prompt,
    build_review_prompt,
    load_schema,
    write_schema_file,
)

IGNORED_REVIEW_ARTIFACT_DIRS = {
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "htmlcov",
}
IGNORED_REVIEW_ARTIFACT_SUFFIXES = {
    ".pyc",
    ".pyo",
}
IGNORED_REVIEW_ARTIFACT_NAMES = {
    ".coverage",
}
DEFAULT_CODEX_MODEL = "gpt-5.4"
DEFAULT_REASONING_EFFORT = "xhigh"


def run_implementation(request_path: Path) -> Path:
    """Run implementation mode and write the standardized output."""
    request = parse_implementation_request(request_path)
    _ensure_repository(request.repository)
    prompt = build_implementation_prompt(request)
    result = _invoke_codex(
        "implement",
        request.repository,
        prompt,
        sandbox="workspace-write",
    )
    request.output_path.write_text(_render_implementation_output(result), encoding="utf-8")
    return request.output_path


def run_review(request_path: Path) -> Path:
    """Run review mode and write the standardized output."""
    request = parse_review_request(request_path)
    _ensure_repository(request.repository)
    before = _snapshot_repository(request.repository)
    prompt = build_review_prompt(request)
    result = _invoke_codex(
        "review",
        request.repository,
        prompt,
        sandbox="read-only",
    )
    after = _snapshot_repository(request.repository)
    if after != before:
        raise WorkflowViolationError(
            "Review mode changed repository state before the runner wrote Output File."
        )
    output_path = request.output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(_render_review_output(result), encoding="utf-8")
    final = _snapshot_repository(request.repository)
    changed = _changed_paths(before, final)
    allowed = {output_path.resolve()}
    unauthorized = sorted(path for path in changed if path not in allowed)
    if unauthorized:
        raise WorkflowViolationError(
            "Review mode modified files outside Output File: "
            + ", ".join(str(path) for path in unauthorized)
        )
    return output_path


def _invoke_codex(
    mode: str,
    repository: Path,
    prompt: str,
    sandbox: str,
) -> dict:
    with tempfile.TemporaryDirectory(prefix="codex-flow-") as tempdir:
        temp_path = Path(tempdir)
        schema_path = write_schema_file(load_schema(mode), temp_path, mode)
        output_path = temp_path / f"{mode}-response.json"
        command = [
            "codex",
            "exec",
            "--model",
            DEFAULT_CODEX_MODEL,
            "--config",
            f"model_reasoning_effort={DEFAULT_REASONING_EFFORT}",
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check",
            "--cd",
            str(repository),
            "--output-schema",
            str(schema_path),
            "--output-last-message",
            str(output_path),
            "-",
        ]
        try:
            subprocess.run(
                command,
                input=prompt,
                text=True,
                capture_output=True,
                check=True,
            )
        except subprocess.CalledProcessError as err:
            raise WorkflowViolationError(
                f"codex exec failed with exit code {err.returncode}: {err.stderr.strip()}"
            ) from err

        if not output_path.exists():
            raise WorkflowViolationError("codex exec completed without producing a final response.")
        try:
            parsed = json.loads(output_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as err:
            raise WorkflowViolationError("codex exec returned invalid JSON output.") from err
        if not isinstance(parsed, dict):
            raise WorkflowViolationError("codex exec returned a non-object JSON response.")
        return cast(dict[Any, Any], parsed)


def _ensure_repository(path: Path) -> None:
    if not path.exists():
        raise ValidationError(f"Repository does not exist: {path}")
    if not path.is_dir():
        raise ValidationError(f"Repository path is not a directory: {path}")


def _snapshot_repository(repository: Path) -> dict[Path, tuple[int, int]]:
    snapshot: dict[Path, tuple[int, int]] = {}
    for path in repository.rglob("*"):
        if not path.is_file():
            continue
        if ".git" in path.parts:
            continue
        if _is_ignored_review_artifact(path, repository):
            continue
        stat = path.stat()
        snapshot[path.resolve()] = (stat.st_size, stat.st_mtime_ns)
    return snapshot


def _changed_paths(
    before: dict[Path, tuple[int, int]], after: dict[Path, tuple[int, int]]
) -> set[Path]:
    changed: set[Path] = set()
    for path in set(before) | set(after):
        if before.get(path) != after.get(path):
            changed.add(path)
    return changed


def _is_ignored_review_artifact(path: Path, repository: Path) -> bool:
    relative_path = path.resolve().relative_to(repository.resolve())
    if any(part in IGNORED_REVIEW_ARTIFACT_DIRS for part in relative_path.parts):
        return True
    if path.name in IGNORED_REVIEW_ARTIFACT_NAMES:
        return True
    return path.suffix in IGNORED_REVIEW_ARTIFACT_SUFFIXES


def _render_implementation_output(result: dict) -> str:
    verification_lines = []
    for item in result["verification_results"]:
        verification_lines.append(f"- `{item['command']}` — {item['status']}: {item['details']}")

    files_changed = [f"- `{path}`" for path in result["files_changed"]] or ["- None reported"]
    reasoning = [f"- {item}" for item in result["reasoning"]] or ["- None"]
    open_issues = [f"- {item}" for item in result["open_issues"]] or ["- None"]

    return "\n".join(
        [
            "# Implementation Output",
            "",
            f"**Final Status:** `{result['final_status']}`",
            "",
            "## Summary",
            result["summary"],
            "",
            "## Files Changed",
            *files_changed,
            "",
            "## Verification Results",
            *(verification_lines or ["- None reported"]),
            "",
            "## Concise Reasoning",
            *reasoning,
            "",
            "## Open Issues",
            *open_issues,
            "",
        ]
    )


def _render_review_output(result: dict) -> str:
    findings = []
    for item in result["findings"]:
        findings.extend(
            [
                f"### {item['severity']}: {item['title']}",
                item["evidence"],
                "",
                f"Recommendation: {item['recommendation']}",
                "",
            ]
        )

    coverage = []
    for item in result["requirement_coverage"]:
        coverage.append(f"- `{item['status']}` {item['requirement']}: {item['notes']}")
    gaps = [f"- {item}" for item in result["verification_gaps"]] or ["- None"]

    return "\n".join(
        [
            "# Review Output",
            "",
            f"**Final Status:** `{result['final_status']}`",
            "",
            "## Summary",
            result["summary"],
            "",
            "## Findings By Severity",
            *(findings or ["No findings."]),
            "",
            "## Requirement Coverage",
            *(coverage or ["- No requirement coverage reported."]),
            "",
            "## Verification Gaps",
            *gaps,
            "",
            "## Recommendation",
            result["recommendation"],
            "",
        ]
    )
