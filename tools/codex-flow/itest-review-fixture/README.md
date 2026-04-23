# codex-flow review smoke repo

Small standalone repository fixture for testing `codex-flow review`.

Expected experiment:
- the fixture starts with a committed baseline
- setup adds an uncommitted greeting-helper change
- `codex-flow review` inspects the working tree and writes the review artifact
