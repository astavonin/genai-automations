See:

`platforms/claude/skills/workflows/planning/DESIGN-TEMPLATE.md`

For `codex-flow`, `## 3. Implementation Context` is the authoritative execution contract inside the design document.

Codex implementation responsibilities:
- implement the specified requirements and constraints, not a broader redesign
- trace each requirement to code, tests, or verification evidence
- use the listed build, test, and debug commands when available
- when CI behavior is in scope, inspect real CI job/pipeline evidence during development and run or trigger the relevant CI verification; if blocked, report the exact CI entry point needed
- when the task is device-verifiable from the spec, project guidance, verifier scripts, CI/HIL jobs, or changed code path, run the required on-device verification before claiming completion; if blocked, report the implementation as incomplete with the exact device entry point needed
- if the design doc contains a concrete `On-Device Verification` block, execute that block as part of implementation verification without waiting for an explicit follow-up request
- report any requirement that could not be implemented or verified
