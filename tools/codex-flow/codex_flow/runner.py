"""Workflow execution for codex-flow."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
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
    ".venv",
    "venv",
    "node_modules",
    ".claude",  # Claude Code session/settings files managed by the IDE, not by Codex
    ".codex-flow",  # codex-flow diagnostics, not repository content under review
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
VALID_CODEX_SANDBOXES = {"read-only", "workspace-write", "danger-full-access"}


def run_implementation(request_path: Path) -> Path:
    """Run implementation mode and write the standardized output."""
    request = parse_implementation_request(request_path)
    _ensure_repository(request.repository)
    prompt = build_implementation_prompt(request)
    result = _invoke_codex(
        "implement",
        request.repository,
        prompt,
        sandbox="danger-full-access",
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
    after_codex = _snapshot_repository(request.repository)
    output_path = request.output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(_render_review_output(result), encoding="utf-8")
    final = _snapshot_repository(request.repository)
    changed_during_codex = _changed_paths(before, after_codex)
    changed = _changed_paths(before, final)
    unexpected = sorted(path for path in changed if path != output_path.resolve())
    if unexpected:
        trace_path = _write_review_change_trace(
            request.repository,
            output_path,
            changed_during_codex,
            unexpected,
        )
        _warn_review_changes(request.repository, unexpected, trace_path)
    return output_path


def _invoke_codex(
    mode: str,
    repository: Path,
    prompt: str,
    sandbox: str,
) -> dict:
    if sandbox not in VALID_CODEX_SANDBOXES:
        raise WorkflowViolationError(f"Unsupported Codex sandbox mode: {sandbox}")

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
        ]
        if sandbox == "danger-full-access":
            command.append("--dangerously-bypass-approvals-and-sandbox")
        else:
            command.extend(
                [
                    "--ignore-user-config",
                    "--ignore-rules",
                    "--config",
                    "approval_policy=never",
                    "--sandbox",
                    sandbox,
                ]
            )
        command.extend(
            [
                "--skip-git-repo-check",
                "--cd",
                str(repository),
                "--output-schema",
                str(schema_path),
                "--output-last-message",
                str(output_path),
                "-",
            ]
        )
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


def _write_review_change_trace(
    repository: Path,
    output_path: Path,
    changed_during_codex: set[Path],
    unexpected: list[Path],
) -> Path:
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
    safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", output_path.stem).strip("-")
    trace_name = f"{safe_stem or 'review'}-{timestamp}.json"
    trace_dir = repository / ".codex-flow" / "review-traces"
    trace_dir.mkdir(parents=True, exist_ok=True)
    trace_path = trace_dir / trace_name
    payload = {
        "event": "review_mode_repository_changed",
        "timestamp_utc": timestamp,
        "repository": str(repository.resolve()),
        "output_file": str(output_path.resolve()),
        "changed_during_codex": [
            _display_repository_path(path, repository) for path in sorted(changed_during_codex)
        ],
        "unexpected_changed_paths": [
            _display_repository_path(path, repository) for path in unexpected
        ],
    }
    trace_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return trace_path


def _warn_review_changes(repository: Path, changed_paths: list[Path], trace_path: Path) -> None:
    displayed_paths = [_display_repository_path(path, repository) for path in changed_paths]
    preview = ", ".join(displayed_paths[:5])
    if len(displayed_paths) > 5:
        preview = f"{preview}, ... ({len(displayed_paths)} total)"
    print(
        "codex-flow warning: review mode observed repository changes outside Output File; "
        f"review output was preserved. Changed paths: {preview}. Trace: {trace_path}",
        file=sys.stderr,
    )


def _display_repository_path(path: Path, repository: Path) -> str:
    try:
        return path.resolve().relative_to(repository.resolve()).as_posix()
    except ValueError:
        return str(path)


def _is_ignored_review_artifact(path: Path, repository: Path) -> bool:
    try:
        relative_path = path.resolve().relative_to(repository.resolve())
    except ValueError:
        # Symlink target resolves outside the repository (e.g. .venv → /usr/bin/python)
        return True
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
