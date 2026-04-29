# Review Request - codex-flow Progress Reporting

**Repository:** `/home/astavonin/projects/genai-automations/tools/codex-flow`
**Review Scope:** `working-tree`
**Output File:** `planning/reviews/codex-flow-progress-review.md`

## Requirements

- Support progress reporting for both `codex-flow implement` and `codex-flow review`.
- Keep final output paths on stdout and send progress to stderr.
- Support `--progress plain`, `--progress json`, and `--progress quiet`.
- Support `--no-progress-log`.
- Persist normalized progress logs outside the target repository by default.
- Do not persist raw Codex JSON traces.
- Keep implementation mode automatic with full access.
- Keep review mode read-only with runtime sandbox enforcement.
- Preserve the existing standardized Markdown output behavior.

## Constraints

- Do not modify repository files during review except the requested `Output File`.
- Keep changes scoped to codex-flow progress reporting, runtime invocation, docs, and tests.

## Evidence

```bash
.venv/bin/black --check codex_flow tests
.venv/bin/flake8 codex_flow tests
.venv/bin/mypy codex_flow
.venv/bin/pytest
```

## Review Focus

- correctness
- runtime sandbox enforcement
- stdout and stderr behavior
- persisted progress log behavior
- regression risk
- test coverage
