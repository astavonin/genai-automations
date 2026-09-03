"""Tests for codex-flow runtime behavior."""

from __future__ import annotations

import json
import io
import subprocess
from pathlib import Path
from typing import Callable

import pytest

from codex_flow.exceptions import CodexFlowError, WorkflowViolationError
from codex_flow.progress import PROGRESS_MARKER, ProgressConfig, repository_state_key
from codex_flow.runner import (
    DEFAULT_CODEX_MODEL,
    DISABLED_EXTERNAL_TOOL_FEATURES,
    MAX_CODEX_DIAGNOSTIC_CHARS,
    MAX_CODEX_DIAGNOSTIC_LINES,
    UNKNOWN_CODEX_ACTIVITY_INTERVAL,
    run_implementation,
    run_review,
)

# Every test here drives a whole workflow end to end — request parsing, prompt building, the
# subprocess contract, stream handling, and output rendering composed — with only the `codex`
# process itself replaced. That composition is what the observed failures crossed.
pytestmark = pytest.mark.integration


class _RecordingStdin(io.StringIO):
    """Stdin double that survives `close()` so the delivered prompt stays assertable."""

    def __init__(self) -> None:
        super().__init__()
        self.written = ""

    def write(self, text: str) -> int:  # type: ignore[override]
        self.written += text
        return len(text)


class _FakeProcess:
    def __init__(self, stdout_text: str = "", return_code: int = 0) -> None:
        self.stdin = _RecordingStdin()
        self.stdout = io.StringIO(stdout_text)
        self._return_code = return_code
        self.killed = False

    def wait(self) -> int:
        return self._return_code

    def kill(self) -> None:
        self.killed = True


def _install_fake_popen(
    monkeypatch: pytest.MonkeyPatch,
    on_start: Callable[[list[str]], None],
    stdout_text: str = "",
    return_code: int = 0,
) -> list[_FakeProcess]:
    """Replace `codex exec` with a scripted process; returns the list of spawned fakes."""
    spawned: list[_FakeProcess] = []

    def fake_popen(
        command: list[str],
        stdin: int,
        stdout: int,
        stderr: int,
        text: bool,
        bufsize: int,
    ) -> _FakeProcess:
        assert stdin == subprocess.PIPE
        assert stdout == subprocess.PIPE
        assert stderr == subprocess.STDOUT
        assert text is True
        assert bufsize == 1
        on_start(command)
        process = _FakeProcess(stdout_text, return_code)
        spawned.append(process)
        return process

    monkeypatch.setattr("codex_flow.runner.subprocess.Popen", fake_popen)
    return spawned


def _config_values(command: list[str]) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command) if value == "--config"]


def _disabled_features(command: list[str]) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command) if value == "--disable"]


def _write_implementation_request(path: Path, repository: Path) -> None:
    path.write_text(
        f"""
# Design — Retry Handling

## 3. Implementation Context

**Repository:** `{repository}`

**Functional Requirements:**
- Retry transient failures up to three times

**Non-Functional Requirements:**
- Retry must add no more than 50 ms latency per attempt

**Constraints:**
- Keep the CLI unchanged

**Verification:**
```bash
pytest tests/test_sync.py
```

**Context Files:**
- `src/sync.py`
""".strip(),
        encoding="utf-8",
    )


def _write_review_request(path: Path, repository: Path) -> None:
    path.write_text(
        f"""
# Review Request — Retry Handling

**Repository:** `{repository}`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/retry-review.md`

## Requirements

- Retry transient failures up to three times

## Constraints

- Keep the CLI unchanged

## Evidence

```bash
pytest tests/test_sync.py
```

## Observed-Failure Ledger

No ledger exists for this work.

## Review Focus

- correctness
""".strip(),
        encoding="utf-8",
    )


def _write_implementation_response(command: list[str]) -> None:
    output_index = command.index("--output-last-message") + 1
    Path(command[output_index]).write_text(
        json.dumps(
            {
                "final_status": "SUCCESS",
                "summary": "Implemented retry handling.",
                "files_changed": ["src/sync.py"],
                "verification_results": [
                    {
                        "command": "pytest tests/test_sync.py",
                        "status": "passed",
                        "details": "1 passed",
                    }
                ],
                "reasoning": ["Kept the CLI unchanged."],
                "open_issues": [],
            }
        ),
        encoding="utf-8",
    )


def _make_implementation_repo(tmp_path: Path) -> Path:
    """Create the implementation fixture repo; returns the request path."""
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "src").mkdir()
    (repository / "src/sync.py").write_text("print('ok')\n", encoding="utf-8")
    request = tmp_path / "design.md"
    _write_implementation_request(request, repository)
    return request


def test_run_implementation_invokes_codex_with_full_access_sandbox(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    request = _make_implementation_repo(tmp_path)

    def on_start(command: list[str]) -> None:
        assert command[:2] == ["codex", "exec"]
        assert "--json" in command
        assert "--ignore-user-config" not in command
        assert "--ignore-rules" not in command
        assert "--model" in command
        assert command[command.index("--model") + 1] == DEFAULT_CODEX_MODEL
        assert _config_values(command) == ["model_reasoning_effort=xhigh"]
        assert _disabled_features(command) == list(DISABLED_EXTERNAL_TOOL_FEATURES)
        assert "--dangerously-bypass-approvals-and-sandbox" in command
        assert "--sandbox" not in command
        _write_implementation_response(command)

    processes = _install_fake_popen(monkeypatch, on_start)

    run_implementation(request)

    assert processes[0].stdin.written.startswith("You are running codex-flow in implementation")


def test_run_implementation_writes_standardized_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    request = _make_implementation_repo(tmp_path)
    _install_fake_popen(monkeypatch, _write_implementation_response)

    output = run_implementation(request)

    assert output.exists()
    content = output.read_text(encoding="utf-8")
    assert "**Final Status:** `SUCCESS`" in content
    assert "`src/sync.py`" in content


def test_run_implementation_reports_codex_error_message_when_codex_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    request = _make_implementation_repo(tmp_path)
    stream = io.StringIO()
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=f'{{"type":"error","message":"{capacity_error}"}}\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_implementation(request, ProgressConfig(mode="plain", log_enabled=False, stream=stream))

    assert capacity_error in str(excinfo.value)
    assert "codex-flow: Implementation workflow failed" in stream.getvalue()


def test_run_review_uses_read_only_and_only_writes_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "file.txt").write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def on_start(command: list[str]) -> None:
        assert command[:2] == ["codex", "exec"]
        assert "--json" in command
        assert "--ignore-user-config" in command
        assert "--ignore-rules" in command
        assert "--model" in command
        assert command[command.index("--model") + 1] == DEFAULT_CODEX_MODEL
        assert _config_values(command) == [
            "model_reasoning_effort=xhigh",
            "approval_policy=never",
        ]
        assert _disabled_features(command) == list(DISABLED_EXTERNAL_TOOL_FEATURES)
        assert "--dangerously-bypass-approvals-and-sandbox" not in command
        assert "--sandbox" in command
        assert command[command.index("--sandbox") + 1] == "read-only"
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [
                        {
                            "requirement": "Retry transient failures up to three times",
                            "status": "verified",
                            "notes": "Behavior matches the diff.",
                        }
                    ],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )

    processes = _install_fake_popen(monkeypatch, on_start)
    stream = io.StringIO()

    output = run_review(request, ProgressConfig(mode="json", log_enabled=False, stream=stream))

    assert output.exists()
    assert output.read_text(encoding="utf-8").startswith("# Review Output")
    # The "only writes output" half of the name: nothing else in the repository moved.
    assert (repository / "file.txt").read_text(encoding="utf-8") == "before\n"
    events = [json.loads(line) for line in stream.getvalue().splitlines()]
    assert any(
        event["phase"] == "repository_check" and event["status"] == "succeeded" for event in events
    )
    assert not any(event["status"] == "warning" for event in events)
    assert processes[0].stdin.written.startswith("You are running codex-flow in review mode.")
    assert "Retry transient failures up to three times" in processes[0].stdin.written


def test_run_review_ignores_pytest_and_pyc_artifacts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "src").mkdir()
    (repository / "tests").mkdir()
    (repository / "file.txt").write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def on_start(command: list[str]) -> None:
        pycache_dir = repository / "src" / "__pycache__"
        pytest_cache_dir = repository / ".pytest_cache" / "v" / "cache"
        pycache_dir.mkdir(parents=True, exist_ok=True)
        pytest_cache_dir.mkdir(parents=True, exist_ok=True)
        (pycache_dir / "example.cpython-312.pyc").write_text("cache", encoding="utf-8")
        (pytest_cache_dir / "nodeids").write_text("[]", encoding="utf-8")
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )

    _install_fake_popen(monkeypatch, on_start)
    stream = io.StringIO()
    state_home = tmp_path / "state"

    output = run_review(
        request,
        ProgressConfig(mode="json", log_enabled=False, state_home=state_home, stream=stream),
    )

    assert output.exists()
    # The artifacts appeared mid-run; treating them as repository changes would warn and trace.
    events = [json.loads(line) for line in stream.getvalue().splitlines()]
    assert any(
        event["phase"] == "repository_check" and event["status"] == "succeeded" for event in events
    )
    assert not any(event["status"] == "warning" for event in events)
    assert not list(state_home.rglob("review-traces/*.json"))


def test_run_review_warns_and_traces_when_repo_changes_during_codex_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    target = repository / "file.txt"
    target.write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    state_home = tmp_path / "state"

    def on_start(command: list[str]) -> None:
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "REQUEST CHANGES",
                    "summary": "A regression is present.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": ["Tests were not rerun."],
                    "recommendation": "Request changes.",
                }
            ),
            encoding="utf-8",
        )
        target.write_text("after\n", encoding="utf-8")

    _install_fake_popen(monkeypatch, on_start)

    output = run_review(request, ProgressConfig(state_home=state_home))

    captured = capsys.readouterr()
    assert output.exists()
    assert output.read_text(encoding="utf-8").startswith("# Review Output")
    assert "codex-flow warning: review mode observed repository changes" in captured.err
    assert "file.txt" in captured.err
    assert not (repository / ".codex-flow").exists()
    trace_files = sorted((state_home / "runs").glob("*/review-traces/*.json"))
    assert len(trace_files) == 1
    trace = json.loads(trace_files[0].read_text(encoding="utf-8"))
    assert trace["event"] == "review_mode_repository_changed"
    assert trace["output_file"] == str(output.resolve())
    assert trace["changed_during_codex"] == ["file.txt"]
    assert trace["unexpected_changed_paths"] == ["file.txt"]


def test_run_review_emits_json_progress_and_external_log(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "file.txt").write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    state_home = tmp_path / "state"

    def on_start(command: list[str]) -> None:
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )

    _install_fake_popen(
        monkeypatch,
        on_start,
        stdout_text='{"type":"tool_call","tool_name":"rg"}\n{"type":"unknown"}\n',
    )

    output = run_review(
        request,
        ProgressConfig(
            mode="json",
            log_enabled=True,
            state_home=state_home,
            stream=stream,
        ),
    )

    assert output.exists()
    progress_events = [json.loads(line) for line in stream.getvalue().splitlines()]
    assert {event["marker"] for event in progress_events} == {PROGRESS_MARKER}
    assert {event["workflow"] for event in progress_events} == {"review"}
    assert any(event.get("tool") == "rg" for event in progress_events)

    repo_key = repository_state_key(repository)
    log_files = sorted((state_home / "runs" / repo_key).glob("*.jsonl"))
    assert len(log_files) == 1
    log_content = log_files[0].read_text(encoding="utf-8")
    assert PROGRESS_MARKER in log_content
    assert "tool_call" not in log_content


def test_run_review_reports_codex_error_message_when_codex_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A failure expressed through the JSON protocol must reach the raised error text.

    Reproduces the 2026-08-27 outage: three review runs died on `server_overloaded` and
    reported only `codex exec failed with exit code 1`, leaving the cause undiagnosable.
    """
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            '{"type":"thread.started","thread_id":"01a0"}\n'
            f'{{"type":"error","message":"{capacity_error}"}}\n'
            f'{{"type":"turn.failed","error":{{"message":"{capacity_error}"}}}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request, ProgressConfig(mode="plain", log_enabled=False, stream=stream))

    message = str(excinfo.value)
    assert "exit code 1" in message
    assert capacity_error in message
    # Codex reports the same failure as `error` and again inside `turn.failed`.
    assert message.count(capacity_error) == 1
    assert f"Codex reported an error: {capacity_error}" in stream.getvalue()


def test_run_review_truncates_an_oversized_codex_error_message(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    oversized = "x" * (MAX_CODEX_DIAGNOSTIC_CHARS + 100)

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=f'{{"type":"error","message":"{oversized}"}}\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert "x" * MAX_CODEX_DIAGNOSTIC_CHARS in str(excinfo.value)
    assert "x" * (MAX_CODEX_DIAGNOSTIC_CHARS + 1) not in str(excinfo.value)


def test_run_review_keeps_the_newest_diagnostics_when_bounded(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The cause is always last on the stream, so the bound must drop the oldest entries."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    overflow = MAX_CODEX_DIAGNOSTIC_LINES + 5

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text="".join(
            f'{{"type":"error","message":"failure {index}"}}\n' for index in range(overflow)
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    reported = str(excinfo.value).splitlines()
    assert len(reported) == MAX_CODEX_DIAGNOSTIC_LINES
    assert f"failure {overflow - 1}" in reported[-1]
    assert "failure 0" not in str(excinfo.value)


def test_run_review_reports_the_cause_arriving_after_the_budget_is_spent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Merged stderr noise must not evict the fatal event that ends the run."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    capacity_error = "Selected model is at capacity. Please try a different model."
    noise = "".join(
        f"2026-08-27T08:37:{index:02d}Z ERROR codex_models_manager: retrying\n"
        for index in range(MAX_CODEX_DIAGNOSTIC_LINES + 5)
    )

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=noise + f'{{"type":"error","message":"{capacity_error}"}}\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert capacity_error in str(excinfo.value)


def test_run_review_reports_a_turn_failed_event_with_no_preceding_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """`turn.failed` carries the cause under a nested key and must be recognized alone."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            '{"type":"thread.started","thread_id":"01a0"}\n'
            '{"type":"turn.started"}\n'
            f'{{"type":"turn.failed","error":{{"message":"{capacity_error}"}}}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request, ProgressConfig(mode="plain", log_enabled=False, stream=stream))

    assert capacity_error in str(excinfo.value)
    assert f"Codex reported an error: {capacity_error}" in stream.getvalue()


def test_run_review_leads_the_failure_message_with_the_fatal_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A non-fatal warning arrives first but must not become the reason an operator triages."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    warning = "Model metadata for `gpt-5.6-terra` not found. Defaulting to fallback metadata."
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            '{"type":"thread.started","thread_id":"01a0"}\n'
            f'{{"type":"item.completed","item":{{"id":"item_0","type":"error",'
            f'"message":"{warning}"}}}}\n'
            '{"type":"turn.started"}\n'
            f'{{"type":"error","message":"{capacity_error}"}}\n'
            f'{{"type":"turn.failed","error":{{"message":"{capacity_error}"}}}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    reported = str(excinfo.value).splitlines()
    assert reported[0] == f"codex exec failed with exit code 1: {capacity_error}"
    # The warning is kept as context but must never be the line an operator triages from.
    assert warning in reported[1]


def test_run_review_deduplicates_a_repeat_separated_by_another_fatal_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A retry loop repeats one failure with other fatal events in between."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            f'{{"type":"error","message":"{capacity_error}"}}\n'
            '{"type":"error","message":"stream disconnected before completion"}\n'
            f'{{"type":"turn.failed","error":{{"message":"{capacity_error}"}}}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request, ProgressConfig(mode="plain", log_enabled=False, stream=stream))

    assert str(excinfo.value).count(capacity_error) == 1
    assert "stream disconnected before completion" in str(excinfo.value)
    # A repeat must not reach the operator twice on the live stream either.
    assert stream.getvalue().count(f"Codex reported an error: {capacity_error}") == 1


def test_run_review_distinguishes_errors_sharing_a_rendered_length_prefix(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Deduplication runs on retained text, which is longer than what gets rendered."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    shared = "y" * (MAX_CODEX_DIAGNOSTIC_CHARS + 10)

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            f'{{"type":"error","message":"{shared}first"}}\n'
            f'{{"type":"error","message":"{shared}second"}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert len(str(excinfo.value).splitlines()) == 2


def test_run_review_reports_plain_text_output_beside_a_message_less_fatal_event(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A fatal event with no usable text must not suppress the crash trace that explains it."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    panic = "thread 'main' panicked at codex-rs/core/src/client.rs:412: provider handshake failed"

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=f'{panic}\n{{"type":"error","status":503,"request_id":"req_9f2"}}\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    reported = str(excinfo.value).splitlines()
    assert reported[0].endswith("error event carried no message")
    assert panic in reported[1]


def test_run_review_bounds_plain_text_output_with_no_fatal_event(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    overflow = MAX_CODEX_DIAGNOSTIC_LINES + 5

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text="".join(f"crash line {index}\n" for index in range(overflow)),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    reported = str(excinfo.value).splitlines()
    assert len(reported) == MAX_CODEX_DIAGNOSTIC_LINES
    assert f"crash line {overflow - 1}" in reported[-1]


def test_run_review_prefers_a_nested_message_over_a_coarser_sibling_key(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A coarse identifier one level up must not outrank an explicit message below it."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            '{"type":"turn.failed","error":{"text":"generic failure",'
            f'"detail":{{"message":"{capacity_error}"}}}}}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert capacity_error in str(excinfo.value)
    assert "generic failure" not in str(excinfo.value)


def test_run_review_prefers_the_error_subtree_over_a_sibling_field(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An unanchored search lets an unrelated sibling outrank the real cause."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            '{"type":"turn.failed","usage":{"details":"turn 3 of 5, 12k cached tokens"},'
            f'"error":{{"message":"{capacity_error}"}}}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert capacity_error in str(excinfo.value)
    assert "12k cached tokens" not in str(excinfo.value)


@pytest.mark.parametrize(
    ("event", "expected"),
    [
        (
            '{"type":"turn.failed","error":"Selected model is at capacity."}',
            "Selected model is at capacity.",
        ),
        ('{"type":"turn.failed","error":{"code":"server_overloaded"}}', "server_overloaded"),
        ('{"type":"error","status":503}', "error event carried no message"),
    ],
)
def test_run_review_reports_error_shapes_without_a_message_field(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, event: str, expected: str
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    _install_fake_popen(monkeypatch, lambda command: None, stdout_text=event + "\n", return_code=1)

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert expected in str(excinfo.value)


def test_run_review_reports_a_non_object_json_line(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A bare JSON string on the merged stream is output too, not a payload to discard."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text='"fatal: unable to reach the model provider"\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert "unable to reach the model provider" in str(excinfo.value)


def test_run_review_removes_a_stale_output_file_when_codex_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Absence must mean failure — the caller's freshness check is the file's existence."""
    repository = tmp_path / "repo"
    repository.mkdir()
    stale = repository / "planning/reviews/retry-review.md"
    stale.parent.mkdir(parents=True)
    stale.write_text("# Review Output\n\nFindings from the previous round.\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text='{"type":"error","message":"Selected model is at capacity."}\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError):
        run_review(request)

    assert not stale.exists()


def test_run_review_keeps_a_stale_output_file_when_codex_never_starts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A missing `codex` binary is no reason to destroy the previous round's review."""
    repository = tmp_path / "repo"
    repository.mkdir()
    stale = repository / "planning/reviews/retry-review.md"
    stale.parent.mkdir(parents=True)
    stale.write_text("# Review Output\n\nFindings from the previous round.\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def fake_popen(*args: object, **kwargs: object) -> None:
        raise OSError("No such file or directory: 'codex'")

    monkeypatch.setattr("codex_flow.runner.subprocess.Popen", fake_popen)

    with pytest.raises(WorkflowViolationError):
        run_review(request)

    assert stale.read_text(encoding="utf-8").startswith("# Review Output")


def test_run_review_kills_codex_when_the_stale_output_cannot_be_removed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Codex is already running by then; escaping without reaping it leaves it on the repo."""
    repository = tmp_path / "repo"
    repository.mkdir()
    # A directory at the output path makes `unlink()` raise from inside the started-callback.
    blocked = repository / "planning/reviews/retry-review.md"
    blocked.mkdir(parents=True)
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    processes = _install_fake_popen(monkeypatch, lambda command: None)

    with pytest.raises(OSError):
        run_review(request)

    assert processes[0].killed


def test_run_review_reports_a_legacy_task_complete_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The legacy terminal event names no marker but carries the provider error under `error`."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    capacity_error = "Selected model is at capacity. Please try a different model."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            '{"type":"task_complete","turn_id":"01a0","error":null}\n'
            f'{{"type":"task_complete","turn_id":"01a1","error":{{"message":"{capacity_error}",'
            '"codex_error_info":"server_overloaded"}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request, ProgressConfig(mode="plain", log_enabled=False, stream=stream))

    assert capacity_error in str(excinfo.value)
    # The successful terminal event carries `error: null` and must stay off the error path.
    assert stream.getvalue().count("Codex reported an error") == 1


def test_run_review_deduplicates_one_message_seen_as_both_warning_and_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Identical text in both channels is one diagnostic, and belongs with the fatal output."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    shared = "Provider returned 529."

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=(
            f'{{"type":"item.completed","item":{{"id":"i0","type":"error","message":"{shared}"}}}}\n'
            '{"type":"error","message":"Stream closed before completion."}\n'
            f'{{"type":"error","message":"{shared}"}}\n'
        ),
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request, ProgressConfig(mode="plain", log_enabled=False, stream=stream))

    reported = str(excinfo.value)
    assert reported.count(shared) == 1
    assert stream.getvalue().count(f"Codex reported an error: {shared}") == 1
    # Promoted to the fatal channel: everything fatal renders before anything non-fatal.
    assert shared in reported.splitlines()[-1]


def test_run_review_keeps_a_stale_output_file_when_the_request_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Validation runs before the output path is known, so absence cannot prove failure here."""
    repository = tmp_path / "repo"
    repository.mkdir()
    stale = repository / "planning/reviews/retry-review.md"
    stale.parent.mkdir(parents=True)
    stale.write_text("# Review Output\n\nFindings from the previous round.\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    request.write_text(
        request.read_text(encoding="utf-8").replace("## Review Focus\n\n- correctness", ""),
        encoding="utf-8",
    )

    with pytest.raises(CodexFlowError):
        run_review(request)

    assert stale.read_text(encoding="utf-8").startswith("# Review Output")


def test_run_review_reports_non_json_output_when_codex_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Codex writes crashes to stderr, which the runner merges into stdout as plain text."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text="thread 'main' panicked at src/main.rs:42\n",
        return_code=101,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert "exit code 101" in str(excinfo.value)
    assert "thread 'main' panicked" in str(excinfo.value)


def test_run_review_treats_a_nested_error_item_as_a_warning(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A non-fatal `error` item must be surfaced without failing an otherwise successful run."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    warning = "Model metadata not found. Defaulting to fallback metadata."

    def on_start(command: list[str]) -> None:
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )

    _install_fake_popen(
        monkeypatch,
        on_start,
        stdout_text=(
            f'{{"type":"item.completed","item":{{"id":"item_0","type":"error",'
            f'"message":"{warning}"}}}}\n'
            '{"type":"item.completed","item":{"id":"item_1","type":"command_execution",'
            '"command":"rg pattern","status":"failed"}}\n'
        ),
    )

    output = run_review(request, ProgressConfig(mode="json", log_enabled=False, stream=stream))

    assert output.exists()
    events = [json.loads(line) for line in stream.getvalue().splitlines()]
    error_events = [event for event in events if event.get("activity") == "error"]
    assert [event["status"] for event in error_events] == ["warning"]
    assert warning in error_events[0]["message"]
    # A failed shell command is not a Codex error — it must stay on the tool path.
    assert any(event.get("tool") == "rg" for event in events)


def test_run_review_reports_a_codex_binary_that_cannot_start(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def fake_popen(*args: object, **kwargs: object) -> None:
        raise OSError("No such file or directory: 'codex'")

    monkeypatch.setattr("codex_flow.runner.subprocess.Popen", fake_popen)

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert "codex exec failed to start" in str(excinfo.value)
    assert "No such file or directory" in str(excinfo.value)


def test_run_review_reaps_codex_when_it_exposes_no_streams(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The process started, so it must be reaped and the stale output must not survive it."""
    repository = tmp_path / "repo"
    repository.mkdir()
    stale = repository / "planning/reviews/retry-review.md"
    stale.parent.mkdir(parents=True)
    stale.write_text("# Review Output\n\nFindings from the previous round.\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    class _StreamlessProcess:
        stdin = None
        stdout = None

        def __init__(self) -> None:
            self.killed = False

        def wait(self) -> int:
            return 1

        def kill(self) -> None:
            self.killed = True

    spawned: list[_StreamlessProcess] = []

    def fake_popen(*args: object, **kwargs: object) -> _StreamlessProcess:
        process = _StreamlessProcess()
        spawned.append(process)
        return process

    monkeypatch.setattr("codex_flow.runner.subprocess.Popen", fake_popen)

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert "did not expose expected process streams" in str(excinfo.value)
    assert spawned[0].killed
    assert not stale.exists()


def test_run_review_counts_an_embedded_line_break_against_the_line_budget(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A JSON message decodes to one entry, and the cap counts entries — so entries are lines."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    sprawling = "\\n".join(
        f"trace line {index}" for index in range(MAX_CODEX_DIAGNOSTIC_LINES + 10)
    )

    _install_fake_popen(
        monkeypatch,
        lambda command: None,
        stdout_text=f'{{"type":"error","message":"{sprawling}"}}\n',
        return_code=1,
    )

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    reported = str(excinfo.value).splitlines()
    assert len(reported) == 1
    assert "trace line 0" in reported[0]


@pytest.mark.parametrize(
    ("response", "expected"),
    [
        (None, "completed without producing a final response"),
        ("not json at all", "returned invalid JSON output"),
        ('["a findings list"]', "returned a non-object JSON response"),
    ],
)
def test_run_review_reports_an_unusable_codex_response(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, response: str | None, expected: str
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def on_start(command: list[str]) -> None:
        if response is None:
            return
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(response, encoding="utf-8")

    _install_fake_popen(monkeypatch, on_start)

    with pytest.raises(WorkflowViolationError) as excinfo:
        run_review(request)

    assert expected in str(excinfo.value)


def test_run_review_emits_a_heartbeat_while_codex_is_silent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Unrecognized events are the only liveness signal during a long silent turn."""
    repository = tmp_path / "repo"
    repository.mkdir()
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()

    def on_start(command: list[str]) -> None:
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )

    _install_fake_popen(
        monkeypatch,
        on_start,
        stdout_text='{"type":"item.updated"}\n' * (UNKNOWN_CODEX_ACTIVITY_INTERVAL * 2),
    )

    run_review(request, ProgressConfig(mode="json", log_enabled=False, stream=stream))

    events = [json.loads(line) for line in stream.getvalue().splitlines()]
    heartbeats = [event for event in events if event.get("activity") == "heartbeat"]
    assert len(heartbeats) == 2
    assert heartbeats[0]["message"] == "Codex is still running"


def test_run_implementation_emits_plain_progress(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "src").mkdir()
    (repository / "src/sync.py").write_text("print('ok')\n", encoding="utf-8")
    request = tmp_path / "design.md"
    _write_implementation_request(request, repository)
    stream = io.StringIO()

    def on_start(command: list[str]) -> None:
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "SUCCESS",
                    "summary": "Implemented retry handling.",
                    "files_changed": ["src/sync.py"],
                    "verification_results": [],
                    "reasoning": [],
                    "open_issues": [],
                }
            ),
            encoding="utf-8",
        )

    _install_fake_popen(
        monkeypatch,
        on_start,
        stdout_text='{"type":"exec_command","cmd":"pytest tests"}\n',
    )

    output = run_implementation(
        request,
        ProgressConfig(mode="plain", log_enabled=False, stream=stream),
    )

    assert output.exists()
    progress = stream.getvalue()
    assert "codex-flow: Parsed implementation request" in progress
    assert "codex-flow: Codex ran tool: pytest" in progress
