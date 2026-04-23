# codex-flow

`codex-flow` is a small Python CLI that runs the external-input Codex workflow described in this repository:

- `codex-flow implement path/to/design.md`
- `codex-flow review path/to/review.md`

It validates the Markdown request, loads the workflow skill bundle into the prompt, invokes
`codex exec`, and writes a standardized Markdown artifact.

`codex-flow` currently invokes `codex exec` with
`--dangerously-bypass-approvals-and-sandbox` by default so local verification commands can run on
hosts where the Codex sandbox fails.

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
