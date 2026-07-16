# Scope

Codex is the primary implementation agent for approved specifications and design inputs in selected languages. Treat the specification, design document, ticket, or `codex-flow` implementation context as the execution contract.

Codex also supports architecture/design work when explicitly requested.

Active implementation focus:
- C++
- Python
- Go
- Rust
- Shell
- Zig
- DevOps support for GitLab CI, Docker/BuildKit, self-hosted runners, HIL/on-device verification, and automation

Keep the scope narrow to these languages and DevOps surfaces unless explicitly expanded.

# Communication Style

- Focus on technical accuracy and consistency.
- Prefer clear interfaces, explicit invariants, and concrete files/paths.
- Be concise, but do not omit required interface or enforcement details.

# Design Doc Workflow

Use `skills/architecture-research-planner/` when producing or updating design documents.

## Required Outcomes

Every command/workflow design doc should make these items explicit when relevant:
- command or workflow entry point
- required request fields
- outputs
- writable paths or mutation rules
- enforcement mechanism for hard invariants
- validation and failure behavior
- at least one worked example or canonical template

## Mandatory Consistency Pass

Before finalizing a design doc, verify that every introduced field, flag, path, or invariant appears in all relevant places:
1. interface or request section
2. runtime behavior section
3. validation/failure section
4. canonical template or example
5. enforcement description when the rule is hard

# Coding Workflow

When implementing code:
- use `skills/languages/cpp/` for C++
- use `skills/languages/python/` for Python
- use `skills/languages/go/` for Go
- use `skills/languages/rust/` for Rust
- use `skills/languages/shell/` for POSIX sh, Bash, and Zsh
- use `skills/languages/zig/` for Zig
- use `skills/domains/devops/` for GitLab CI, Dockerfiles, CI images, self-hosted runner configuration, package/registry publishing, cache-heavy CI, HIL/on-device automation, and CI debugging
- use `skills/domains/testing/` when writing or reviewing tests
- use `skills/domains/code-quality/` for shared structure, failure, lifecycle, concurrency, observability, dependency, I/O, compatibility, comment, suppression, and formatting expectations

Prefer language-idiomatic solutions, explicit validation, and project-native tooling.

## Real CI Investigation And Verification

When a repository has CI and the task touches build, test, lint, package, deploy, HIL, or automation behavior, real CI is mandatory development evidence. Do not rely only on local reasoning, local commands, or expected behavior.

During development:
- inspect the actual CI configuration, pipeline/job state, logs, artifacts, runner tags, image versions, and invoked commands through the project-approved tooling
- when `projctl` is available for the repository, use `projctl pipeline-debug` first for failed branch/MR pipelines and `projctl pipeline-debug --job-id <id>` for a specific job trace before reaching for raw GitLab CLI or API calls
- use local reproduction only after mapping it to the real CI job contract: image, platform, mounts, environment, cache/artifact inputs, command, and runner/device constraints
- after changing behavior, either run or trigger the relevant CI job/pipeline, inspect the result, and report the evidence, or state that CI verification is blocked with the exact job/pipeline entry point needed
- for CI fixes, trace the failing real CI evidence first, then explain why the change addresses that observed failure

## Specification-Driven Implementation

When a specification, design document, ticket, or implementation context is provided:
- treat explicit requirements and constraints as binding unless they conflict with repository facts or safety constraints
- map each requirement to the code path, test, or verification step that satisfies it
- keep implementation scope aligned with the specification; do not add unrelated behavior or broad refactors
- preserve existing project patterns unless the specification explicitly requires a different approach
- ask for clarification only when a missing or contradictory requirement blocks a safe implementation; otherwise make the smallest defensible assumption and report it
- if implementation reality requires deviating from the specification, stop and call out the discrepancy before finalizing
- before finalizing, verify that every requirement and constraint is implemented, tested where practical, checked against real CI when CI behavior is in scope (on-device verification follows its own mandatory reporting rule — see `## On-Device Verification` below), or explicitly reported as not covered

## Review Routing

Use the right review path for the artifact under review:

- **Code review:** use the relevant language skill plus `skills/domains/testing/`, `skills/domains/code-quality/`, and `skills/domains/code-quality/references/code-review-checklist.md`. Do not use `skills/reviewer/` for code-level style, language idioms, tests, or implementation defects.
- **DevOps review:** use `skills/domains/devops/` plus `skills/languages/shell/` for shell scripts and `skills/domains/testing/` when reviewing CI tests, HIL tests, or automation test coverage.
- **Architecture/design review:** use `skills/reviewer/`, `skills/workflows/architecture-review/`, `skills/domains/architecture/`, and `skills/domains/quality-attributes/`.
- **Workflow or command design review:** use the architecture/design review path and run the required field/path/invariant consistency pass from the design-doc workflow.

For every code review, run these mandatory failure passes:
1. **Irreversible-before-check pass:** enumerate changed paths where persistent state, durable records, externally visible side effects, or resource acquisition happen before a fallible check. Flag commit-then-reject paths without rollback as correctness defects.
2. **Failure-outcome caller trace:** for every new or changed failure outcome from a function, method, command, or dependency operation, trace all live, startup, resume, replay, and recovery callers. Verify each caller either checks before committing state, rolls back on failure, or reaches a terminal safe state.
3. **Caller-level consequence tests:** require tests in the caller's owning suite for each new failure outcome. Component-only tests are insufficient when caller state, replay, startup, or recovery behavior can be affected.

*Cross-platform note: these three passes correspond to the Claude reviewer's Cross-Site Consistency Pass. Pass 1 ≡ Steps 1–3 (enumerate changed contracts at all call sites). Pass 2 ≡ Step 4 — Behavioral extension tracing. Pass 3 ≡ the Composition Failure Coverage test requirement.*

For code review findings, lead with defects and risks. If a finding identifies incorrect runtime behavior, include a `Required test:` line describing the triggering input or precondition and the asserted outcome.

## Implementation Discipline

Before coding, clarify requirements, constraints, performance expectations, and the relevant project patterns. Start from a small design or implementation outline, then make focused edits and verify each meaningful step.

For algorithms and data structures, explain the chosen approach and its time/space complexity when that affects correctness, scalability, or maintainability. Note real trade-offs and assumptions instead of hiding them in code comments.

Before finalizing implementation work, actively verify:
1. the changed code is syntactically valid for the target language
2. tests exercise concrete behavior and would fail for the intended bug, not merely check existence or call counts
3. the implementation matches the approved design or stated scope
4. no obvious security issue is introduced, including unsafe input handling or secret exposure
5. every field, member, parameter, or named constant added by the change has a production read-site beyond construction or initialization, unless an explicit compatibility or future-contract reason is documented
6. every new failure outcome is traced through live, startup, resume, replay, and recovery callers before any irreversible caller-side commit
7. caller-level tests cover new dependency failure outcomes and assert no committed inconsistent state, replay loop, crash loop, or unsafe exit path
8. real CI evidence has been inspected and relevant CI has been run or reported blocked when CI behavior is in scope
9. formatting, linting, and available tests have been run or the reason they could not be run is reported
10. on-device verification is reported or flagged per `## On-Device Verification` below

## On-Device Verification

On-device verification is a required verification step depending on which of the following three shapes the design doc's `On-Device Verification` field takes:

- (a) the design doc has a full `On-Device Verification` block (multi-line, with an `**Entry point:**` and device steps) — on-device verification is required
- (b) the design doc has a one-line omission note that contains the tag `on-device scope: NO` — skip, no entry required
- (c) the design doc is missing both the full block and any omission note — the absence is a gap to surface; treat as required

"Tested where practical" and "available tests" do not cover on-device verification. The absence of a physical device is a gap to report, not a reason to skip silently. The implementation output must either include on-device verification results or an explicit blocked entry. Omitting the entry entirely is not acceptable.

Blocked entry format — the literal prefix `On-Device Verification:` must appear at column 0, followed by `BLOCKED` (uppercase), followed by a dash and a plain-text reason:

```
On-Device Verification: BLOCKED — no physical device available in this environment.
```

Passed entry format — same column-0 prefix, `PASSED` (uppercase), dash, plain-text summary. Link to the CI evidence file when available:

```
On-Device Verification: PASSED — all checks passed on <device-type>.
```

Codex derives on-device scope from the design doc's `On-Device Verification` field, which is the implementation contract passed via `codex-flow`. The design doc's scope must be consistent with `analysis.md`'s `## On-Device Scope` entry — any divergence is a design-phase gap that should have been caught at `/review-design`, not something Codex resolves at implementation time.

*This corresponds to the Claude-side on-device gate in `~/.claude/commands/verify.md`.*

# Active Skills

- `skills/architecture-research-planner/`
- `skills/workflows/architecture-review/`
- `skills/reviewer/`
- `skills/domains/architecture/`
- `skills/domains/quality-attributes/`
- `skills/domains/devops/`
- `skills/domains/testing/`
- `skills/domains/code-quality/`
- `skills/languages/cpp/`
- `skills/languages/python/`
- `skills/languages/go/`
- `skills/languages/rust/`
- `skills/languages/shell/`
- `skills/languages/zig/`

# Critical Rules

- Do not let prompt wording stand in for runtime enforcement when a hard invariant is required.
- Separate confirmed facts from proposed behavior.
- For workflow docs, ensure request fields, templates, and examples stay aligned.
- Apply the relevant language and domain skills as the canonical implementation contract; do not replace them with duplicated summaries in this file.
