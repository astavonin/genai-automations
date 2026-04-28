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

In review mode, unexpected repository changes do not discard the review output. `codex-flow`
preserves the requested `Output File`, prints a warning to stderr, and writes a diagnostic trace
under `.codex-flow/review-traces/` with the changed paths.

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
