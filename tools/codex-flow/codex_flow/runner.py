"""Workflow execution for codex-flow."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import threading
from collections import deque
from datetime import UTC, datetime
from pathlib import Path
from collections.abc import Callable
from typing import Any, cast

from .exceptions import ValidationError, WorkflowViolationError
from .markdown_parser import parse_implementation_request, parse_review_request
from .prompting import (
    build_implementation_prompt,
    build_review_prompt,
    load_schema,
    write_schema_file,
)
from .progress import ProgressConfig, ProgressReporter, repository_state_dir

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
DEFAULT_CODEX_MODEL = "gpt-5.6-terra"
DEFAULT_REASONING_EFFORT = "xhigh"
VALID_CODEX_SANDBOXES = {"read-only", "workspace-write", "danger-full-access"}
DISABLED_EXTERNAL_TOOL_FEATURES = (
    "apps",
    "plugins",
    "tool_search",
    "tool_suggest",
    "skill_mcp_dependency_install",
    "tool_call_mcp_elicitation",
)
UNKNOWN_CODEX_ACTIVITY_INTERVAL = 25
MAX_CODEX_DIAGNOSTIC_LINES = 20
MAX_CODEX_DIAGNOSTIC_CHARS = 500
# Retained text is longer than rendered text so that deduplication still discriminates between
# two errors sharing a long prefix, while staying bounded.
MAX_CODEX_DIAGNOSTIC_STORED_CHARS = MAX_CODEX_DIAGNOSTIC_CHARS * 8
CODEX_ERROR_EVENT_MARKERS = ("error", "failed")
CODEX_ERROR_PAYLOAD_KEYS = ("error",)
# Searched in two passes over the error subtree. One ordered tuple cannot express the preference:
# `_first_string_for_keys()` tries every key at a level before descending, so a coarse identifier
# one level up would outrank an explicit `message` below it.
CODEX_ERROR_MESSAGE_KEYS = ("message", "reason", "details")
CODEX_ERROR_FALLBACK_KEYS = ("text", "error_type", "code")


def run_implementation(request_path: Path, progress_config: ProgressConfig | None = None) -> Path:
    """Run implementation mode and write the standardized output."""
    request = parse_implementation_request(request_path)
    reporter = ProgressReporter("implement", request.repository, progress_config)
    try:
        reporter.emit("request_parse", "succeeded", "Parsed implementation request")
        _ensure_repository(request.repository)
        prompt = build_implementation_prompt(request)
        reporter.emit("codex_exec", "started", "Starting Codex implementation")
        result = _invoke_codex(
            "implement",
            request.repository,
            prompt,
            sandbox="danger-full-access",
            reporter=reporter,
        )
        reporter.emit("codex_exec", "succeeded", "Codex implementation completed")
        reporter.emit("output_write", "running", "Writing implementation output")
        request.output_path.write_text(_render_implementation_output(result), encoding="utf-8")
        reporter.emit(
            "output_write",
            "succeeded",
            "Wrote implementation output",
            output_file=str(request.output_path.resolve()),
        )
        reporter.emit("workflow_complete", "succeeded", "Implementation workflow completed")
        return request.output_path
    except Exception:
        reporter.emit("workflow_failed", "failed", "Implementation workflow failed")
        raise


def run_review(request_path: Path, progress_config: ProgressConfig | None = None) -> Path:
    """Run review mode and write the standardized output."""
    request = parse_review_request(request_path)
    reporter = ProgressReporter("review", request.repository, progress_config)
    try:
        reporter.emit("request_parse", "succeeded", "Parsed review request")
        _ensure_repository(request.repository)
        reporter.emit("repository_snapshot", "running", "Snapshotting repository")
        before = _snapshot_repository(request.repository)
        reporter.emit("repository_snapshot", "succeeded", "Repository snapshot captured")
        prompt = build_review_prompt(request)
        output_path = request.output_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        reporter.emit("codex_exec", "started", "Starting Codex review")
        result = _invoke_codex(
            "review",
            request.repository,
            prompt,
            sandbox="read-only",
            reporter=reporter,
            # Once Codex is running, the previous run's review is superseded and must not
            # survive a failure: the caller's freshness check is the file's existence, so a
            # stale file would be aggregated as this run's cross-check. Deferred until the
            # process actually starts so a missing `codex` binary does not destroy it.
            on_started=lambda: output_path.unlink(missing_ok=True),
        )
        reporter.emit("codex_exec", "succeeded", "Codex review completed")
        after_codex = _snapshot_repository(request.repository)
        reporter.emit("output_write", "running", "Writing review output")
        output_path.write_text(_render_review_output(result), encoding="utf-8")
        reporter.emit(
            "output_write",
            "succeeded",
            "Wrote review output",
            output_file=str(output_path.resolve()),
        )
        reporter.emit("repository_check", "running", "Checking repository changes")
        final = _snapshot_repository(request.repository)
        changed_during_codex = _changed_paths(before, after_codex) - {output_path.resolve()}
        changed = _changed_paths(before, final)
        unexpected = sorted(path for path in changed if path != output_path.resolve())
        if unexpected:
            trace_path = _write_review_change_trace(
                request.repository,
                output_path,
                changed_during_codex,
                unexpected,
                reporter.state_home,
            )
            reporter.emit(
                "repository_check",
                "warning",
                "Repository changed outside Output File",
                changed_paths=len(unexpected),
                trace=str(trace_path),
            )
            _warn_review_changes(request.repository, unexpected, trace_path)
        else:
            reporter.emit(
                "repository_check",
                "succeeded",
                "Repository unchanged outside Output File",
            )
        reporter.emit("workflow_complete", "succeeded", "Review workflow completed")
        return output_path
    except Exception:
        reporter.emit("workflow_failed", "failed", "Review workflow failed")
        raise


def _invoke_codex(
    mode: str,
    repository: Path,
    prompt: str,
    sandbox: str,
    reporter: ProgressReporter,
    on_started: Callable[[], None] | None = None,
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
            "--json",
            "--model",
            DEFAULT_CODEX_MODEL,
            "--config",
            f"model_reasoning_effort={DEFAULT_REASONING_EFFORT}",
        ]
        for feature in DISABLED_EXTERNAL_TOOL_FEATURES:
            command.extend(["--disable", feature])
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
            process = subprocess.Popen(
                command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except OSError as err:
            raise WorkflowViolationError(f"codex exec failed to start: {err}") from err

        if process.stdin is None or process.stdout is None:
            raise WorkflowViolationError("codex exec did not expose expected process streams.")

        # Everything from here to `wait()` runs with a live child process. Any escape that does
        # not reap it — an `on_started` that raises, an interrupt mid-stream — leaves Codex
        # running against the repository after codex-flow has exited.
        try:
            if on_started is not None:
                on_started()

            writer = threading.Thread(
                target=_write_codex_stdin,
                args=(process.stdin, prompt),
                daemon=True,
            )
            writer.start()
            diagnostics = _stream_codex_progress(process.stdout, reporter)
            return_code = process.wait()
            writer.join(timeout=1)
        except BaseException:
            process.kill()
            process.wait()
            raise
        if return_code != 0:
            details = diagnostics.details()
            suffix = f": {details}" if details else ""
            raise WorkflowViolationError(f"codex exec failed with exit code {return_code}{suffix}")

        if not output_path.exists():
            raise WorkflowViolationError("codex exec completed without producing a final response.")
        try:
            parsed = json.loads(output_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as err:
            raise WorkflowViolationError("codex exec returned invalid JSON output.") from err
        if not isinstance(parsed, dict):
            raise WorkflowViolationError("codex exec returned a non-object JSON response.")
        return cast(dict[Any, Any], parsed)


def _write_codex_stdin(stdin: Any, prompt: str) -> None:
    try:
        stdin.write(prompt)
        stdin.close()
    except BrokenPipeError:
        return


class CodexDiagnostics:
    """Codex output retained for the failure message, fatal kept apart from everything else.

    Two properties matter and neither is incidental. **Fatal leads:** a non-fatal complaint
    arrives before the event that ends the run, and `cli.main()` renders only the first line as
    the reason — so a shared list would headline a benign warning and send an operator to the
    wrong recovery. **Newest wins:** the cause is always last on the stream, so a bound that
    drops the newest entries discards the one line the operator needs.
    """

    def __init__(self) -> None:
        self._fatal: deque[str] = deque(maxlen=MAX_CODEX_DIAGNOSTIC_LINES)
        self._other: deque[str] = deque(maxlen=MAX_CODEX_DIAGNOSTIC_LINES)

    def record(self, detail: str, *, fatal: bool) -> bool:
        """Retain one diagnostic line; False when it repeats something already held.

        Codex reports one failure twice — as its own `error` event and again inside
        `turn.failed` — and a retry loop repeats it further apart, so the comparison covers
        everything retained rather than only the previous entry, in either channel.
        """
        stripped = detail.strip()[:MAX_CODEX_DIAGNOSTIC_STORED_CHARS]
        if stripped in self._fatal:
            return False
        if stripped in self._other:
            if fatal:
                # The same text seen first as a warning and then as the failure itself belongs
                # with the fatal output, which leads the message. It was already reported once.
                self._other.remove(stripped)
                self._fatal.append(stripped)
            return False
        (self._fatal if fatal else self._other).append(stripped)
        return True

    def details(self) -> str:
        """Render the retained lines, fatal first, within one shared line budget.

        Fatal leads rather than replaces: a fatal event can carry no usable text at all, and
        when it does not, the real cause is whatever plain-text output preceded it.
        """
        retained = list(self._fatal) + list(self._other)
        return "\n".join(
            line[:MAX_CODEX_DIAGNOSTIC_CHARS] for line in retained[:MAX_CODEX_DIAGNOSTIC_LINES]
        )


def _stream_codex_progress(stdout: Any, reporter: ProgressReporter) -> CodexDiagnostics:
    diagnostics = CodexDiagnostics()
    unknown_events = 0
    for line in stdout:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            # stderr is merged into stdout, so a crash trace arrives here as plain text.
            diagnostics.record(stripped, fatal=False)
            continue
        if not isinstance(payload, dict):
            diagnostics.record(stripped, fatal=False)
            continue
        error = _extract_codex_error(payload)
        if error is not None:
            status, message = error
            # Record first: one failure arrives as two events, and reporting it twice is the
            # noise this whole path exists to reduce.
            if diagnostics.record(message, fatal=status == "failed"):
                reporter.emit(
                    "codex_activity",
                    status,
                    f"Codex reported an error: {message}",
                    activity="error",
                )
            continue
        if _emit_codex_progress(payload, reporter):
            continue
        unknown_events += 1
        if unknown_events % UNKNOWN_CODEX_ACTIVITY_INTERVAL == 0:
            reporter.emit(
                "codex_activity",
                "running",
                "Codex is still running",
                activity="heartbeat",
            )
    return diagnostics


def _extract_codex_error(payload: dict[str, Any]) -> tuple[str, str] | None:
    """Return `(progress status, failure text)` for an error-shaped Codex event, else None.

    Keyed on the thread-events schema of `codex exec --json` as of codex-cli 0.147.0: a fatal
    failure is a top-level `error` or `turn.failed` event, and a non-fatal complaint is an
    `error` item nested inside `item.completed`. Both carry text worth keeping; only the first
    means the run is over.

    Recognition does not depend on the event name alone. The binary also retains a legacy schema
    whose terminal `task_complete` carries its failure under `error` while naming neither marker —
    that is the shape holding the provider error in Codex's own rollout transcripts — so any event
    carrying a populated `error` subtree counts as fatal whatever it is called. A successful
    `task_complete` sets `error` to null and is unaffected.
    """
    event_name = (_first_string_for_keys(payload, ("type", "event", "kind")) or "").lower()
    named_error = any(marker in event_name for marker in CODEX_ERROR_EVENT_MARKERS)
    if named_error or _has_error_subtree(payload):
        message = _codex_error_message(payload)
        # Saying which event arrived beats an empty suffix, and reads as the fallback it is.
        return "failed", message or f"{event_name or 'error'} event carried no message"
    nested = payload.get("item")
    if isinstance(nested, dict) and str(nested.get("type", "")).lower() == "error":
        nested_message = _codex_error_message(nested)
        if nested_message:
            return "warning", nested_message
    return None


def _has_error_subtree(payload: dict[str, Any]) -> bool:
    """True when the payload carries a populated `error` value, whatever the event is called."""
    for key in CODEX_ERROR_PAYLOAD_KEYS:
        candidate = payload.get(key)
        if isinstance(candidate, str) and candidate.strip():
            return True
        if isinstance(candidate, dict) and candidate:
            return True
    return False


def _codex_error_message(payload: dict[str, Any]) -> str | None:
    """Return the failure text, searching the error subtree before anything beside it.

    `_first_string_for_keys()` descends into values in insertion order, so an unanchored search
    lets an unrelated sibling — `usage.details`, say — outrank the real `error.message`.
    """
    subtrees = [payload.get(key) for key in CODEX_ERROR_PAYLOAD_KEYS]
    for subtree in subtrees:
        if isinstance(subtree, str) and subtree.strip():
            return subtree.strip()
    searchable = [subtree for subtree in subtrees if isinstance(subtree, dict)] or [payload]
    for keys in (CODEX_ERROR_MESSAGE_KEYS, CODEX_ERROR_FALLBACK_KEYS):
        for candidate in searchable:
            found = _first_string_for_keys(candidate, keys)
            if found:
                return found
    return None


def _emit_codex_progress(payload: dict[str, Any], reporter: ProgressReporter) -> bool:
    tool = _extract_tool_name(payload)
    if tool:
        reporter.emit(
            "codex_activity",
            "running",
            f"Codex ran tool: {tool}",
            activity="tool",
            tool=tool,
        )
        return True
    return False


def _extract_tool_name(payload: dict[str, Any]) -> str | None:
    direct_tool = _first_string_for_keys(payload, ("tool_name", "tool", "cmd", "command"))
    if direct_tool:
        return direct_tool.split()[0]

    event_name = _first_string_for_keys(payload, ("type", "event", "kind"))
    if event_name and "exec" in event_name.lower():
        return "shell"
    return None


def _first_string_for_keys(value: Any, keys: tuple[str, ...]) -> str | None:
    if isinstance(value, dict):
        for key in keys:
            item = value.get(key)
            if isinstance(item, str) and item.strip():
                return item.strip()
        for item in value.values():
            found = _first_string_for_keys(item, keys)
            if found:
                return found
    elif isinstance(value, list):
        for item in value:
            found = _first_string_for_keys(item, keys)
            if found:
                return found
    return None


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
    state_home: Path,
) -> Path:
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
    safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", output_path.stem).strip("-")
    trace_name = f"{safe_stem or 'review'}-{timestamp}.json"
    trace_dir = repository_state_dir(repository, state_home) / "review-traces"
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
