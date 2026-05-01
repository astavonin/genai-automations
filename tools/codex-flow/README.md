# codex-flow

`codex-flow` is a small Python CLI that runs the external-input Codex workflow described in this repository:

- `codex-flow implement path/to/design.md`
- `codex-flow review path/to/review.md`

It validates the Markdown request, loads the workflow skill bundle into the prompt, invokes
`codex exec`, and writes a standardized Markdown artifact.

`codex-flow` currently invokes `codex exec` with `--model gpt-5.4` and
`-c model_reasoning_effort=xhigh`. Implementation mode uses
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
