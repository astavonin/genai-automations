# codex-flow

`codex-flow` is a small Python CLI that runs the external-input Codex workflow described in this repository:

- `codex-flow implement path/to/design.md`
- `codex-flow review path/to/review.md`

It validates the Markdown request, loads the workflow skill bundle into the prompt, invokes
`codex exec`, and writes a standardized Markdown artifact.

`codex-flow` invokes `codex exec` with the model named by `codex_flow/runner.py` →
`DEFAULT_CODEX_MODEL` and `-c model_reasoning_effort=xhigh`. Implementation mode uses
`--dangerously-bypass-approvals-and-sandbox` so local verification commands can run on hosts where
the Codex sandbox fails. Review mode ignores the user full-access profile and runs Codex with
`--sandbox read-only`; only the `codex-flow` runner writes the requested review `Output File`.
Both modes disable Codex app/plugin/tool-discovery features so workflows stay scoped to the local
repository instead of drifting into GitHub or other external connectors.

In review mode, unexpected repository changes do not discard the review output. `codex-flow`
preserves the requested `Output File`, prints a warning to stderr, and writes a diagnostic trace
under the external codex-flow state directory with the changed paths.

## Progress

Both workflows stream normalized progress to stderr by default. The final Markdown output path is
still printed alone on stdout.

```bash
codex-flow review --progress plain planning/reviews/request.md
codex-flow implement --progress json planning/design.md
codex-flow review --progress quiet --no-progress-log planning/reviews/request.md
```

Progress modes:

- `plain` - concise human-readable lines on stderr.
- `json` - JSONL progress events on stderr.
- `quiet` - no terminal progress.

Every JSON progress event uses this marker:

```json
{"marker":"codex-flow.progress.v1"}
```

Normalized progress logs are persisted outside the target repository unless `--no-progress-log` is
set:

```text
$XDG_STATE_HOME/codex-flow/runs/<repo-hash>/<run-id>.jsonl
~/.local/state/codex-flow/runs/<repo-hash>/<run-id>.jsonl
```

`codex-flow` does not persist raw Codex JSON traces.

## Install

System-wide install, following the `projctl` pattern:

```bash
cd tools/codex-flow
make install
```

By default, `make install` installs the package globally through `pipx` in editable mode, following the `projctl` pattern.
It uses `python3.12` for the `pipx` environment by default. Override that if needed:

```bash
make install PIPX_PYTHON=/full/path/to/python3.12
```

## When a Run Fails

A failed run exits non-zero. **Read the message shape first — it says how far the run got, and
the three stages have different recoveries.**

### Stage 1 — rejected before Codex launched: `codex-flow: <validation message>`

No `codex exec` in the message, and no run log, because validation happens before the run starts.

```text
codex-flow: Review request must include a filled-in Observed-Failure Ledger section
```

Fix the request document, then re-run. The usual cause is a section left as a template
placeholder; `Observed-Failure Ledger` is the newest such section and the one a request written
from memory most often lacks. **A previous run's output file is still on disk** — this stage runs
before the output path is even resolved, so its presence proves nothing about this run.

### Stage 2 — Codex launched but produced nothing usable: `codex-flow: codex exec <problem>`

The `codex exec` prefix without an exit code. Each message names its own cause and all of them
are permanent — re-running unchanged will not help.

| Message | Cause |
|---|---|
| `codex exec failed to start: <os error>` | The `codex` binary is missing or not executable — reinstall the Codex CLI |
| `codex exec did not expose expected process streams.` | The process started without stdio pipes; an environment problem, not a Codex one |
| `codex exec completed without producing a final response.` | Codex exited cleanly without writing its structured answer |
| `codex exec returned invalid JSON output.` | The final message was not JSON |
| `codex exec returned a non-object JSON response.` | The final message was JSON but not an object |

`failed to start` is the only one that leaves a previous run's output intact; the rest run after
Codex started, which is when that file is removed.

### Stage 3 — Codex ran and failed: `codex-flow: codex exec failed with exit code N: <reason>`

`<reason>` is Codex's own error text. **The first line is the reason; later lines are context.**
JSON error events and plain-text crash output both reach it, bounded to the last 20 lines and 500
characters each.

```text
codex-flow: codex exec failed with exit code 1: Selected model is at capacity. Please try a different model.
```

| First line contains | Cause | Recovery |
|---|---|---|
| `at capacity`, `overloaded` | Transient provider capacity | Re-run unchanged. If a second attempt several minutes later also fails, stop and report it — the failure is no longer transient in any useful sense |
| `model is not supported` | The pinned model is unavailable to this account — retired, or not entitled on the current plan | Update `DEFAULT_CODEX_MODEL` in `runner.py` |
| `event carried no message` | Codex reported a failure carrying no text in a shape this version recognizes | Read the rollout transcript below; extend `CODEX_ERROR_MESSAGE_KEYS` or `CODEX_ERROR_FALLBACK_KEYS` if a new shape appears |
| anything else, or no reason at all | Unclassified | Treat as permanent — re-run at most once, then read the rollout transcript below |

A capacity error can strike mid-run, after Codex has already executed tool calls, so a long run
that dies late is not evidence of a different cause.

### Where the evidence lives

The normalized progress events for every run are kept as JSONL under
`$XDG_STATE_HOME/codex-flow/runs/<repo-key>/` (raw Codex JSON traces are not persisted — see
Progress above). Codex keeps its own full transcript at
`~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-*.jsonl` — note the three nested date components —
where the terminal `task_complete` event holds the raw provider error including
`codex_error_info`. The rollout filenames are local time; codex-flow's run ids are UTC.

```bash
python3 -c "
import json,sys
for line in open(sys.argv[1]):
    e=json.loads(line); p=e.get('payload') or {}
    if p.get('type')=='task_complete': print(json.dumps(p.get('error'), indent=2))
" ~/.codex/sessions/2026/08/27/rollout-<id>.jsonl
```

## Ubuntu Codex Sandbox Fix

On Ubuntu 23.10+ / 24.04 hosts, `codex-flow review` can fail before any local command runs with:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

This happens when AppArmor restricts unprivileged user namespaces and `/usr/bin/bwrap` does not have
a profile that explicitly allows `userns`. Activate the scoped fix on any clean machine with:

```bash
cd tools/codex-flow
make codex-sandbox-status
make codex-sandbox-fix
make codex-sandbox-verify
```

`make codex-sandbox-fix` installs `/etc/apparmor.d/codex-bwrap` and reloads it with
`apparmor_parser`. The profile grants `userns,` only to the bubblewrap binary while leaving the
system-wide `kernel.apparmor_restrict_unprivileged_userns` setting intact. If `bwrap` lives somewhere
else, pass its path:

```bash
BWRAP_PATH=/custom/path/bwrap make codex-sandbox-fix
```

Remove the profile with:

```bash
make codex-sandbox-remove
```

## Test

```bash
cd tools/codex-flow
make test
```

`make test` runs pytest through coverage and enforces the configured 80% coverage threshold.

Integration smoke test fixture:

```bash
cd tools/codex-flow
make itest-implement
```

This recreates `/tmp/codex-flow-smoke-repo` from `itest-fixture/` and runs `pytest` there with the
local `codex-flow` virtualenv.

Review smoke test fixture:

```bash
cd tools/codex-flow
make itest-review
```

This recreates `/tmp/codex-flow-review-smoke-repo`, commits the baseline, applies an uncommitted
greeting-helper change for review, and runs `pytest`.
