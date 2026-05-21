---
name: review-code
description: Review code after implementation using reviewer agent
---

# Code Review Command

**MANDATORY CHECKPOINT:** Review implementation after code is written.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Setup

Read review skills before starting:
```
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
Read ~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md
```

## Status Marker Convention (§4)

Every code review file MUST contain exactly one status marker as the **first non-empty line after the H1 title**, within the first 20 lines:

```
**Status:** APPROVED
```

Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED` — all uppercase, no emoji, no verb/noun mixing.

This marker is machine-readable and used by the `/implement` gate (`head -20 <file> | grep -m 1 '^\*\*Status:\*\*'`). A review without the canonical marker will cause the compaction gate to skip at `/implement`.

## File Overwrite Convention (§7.4)

This skill always writes a **single** file `code-review.md` inside the issue folder, **overwriting** any prior content. No versioning suffixes (`-v1`, `-v2`). No appending. Each run replaces. Git history in `planning/` preserves prior reviews if needed. The gate always reads the single latest file.

## Actions

1. Run the **Consensus Review Protocol** (Steps A–E) against the implementation

   > **⚠️ PARALLEL-LAUNCH GATE**
   > Every call in Step A MUST be in **one message**. Splitting across messages serializes the review.
   > Self-check before sending: does this response contain every Agent call AND the `codex-flow` Bash call?
   > If any are missing — stop, add them, then send.

   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate once all four have returned: Steps B–D for Claude consensus, then cross-aggregate with Codex
2. Format consolidated findings as a markdown review report (see Output Format below)
3. **Write the report to `planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md`** (overwriting any prior version)

4. **Verify the status marker** before declaring the review complete:
   ```bash
   head -20 planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md | grep -m 1 '^\*\*Status:\*\*'
   ```
   - If the marker is found with a canonical state (`APPROVED`, `CHANGES REQUESTED`, or `REJECTED`) → proceed.
   - If the marker is missing or malformed → **do not declare the review complete**. Surface an error and either re-invoke the reviewer agent or ask the user to add the marker manually before continuing.

5. After writing, ask the user if they want to `open <path>` the review file
6. Block until approved

## Final Step — Push planning to backup

After the review file is written and the marker verified, push planning state to backup:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment. If the push fails, surface the elevated warning (see §6.3):

```
⚠️  workflow-safety: planning push failed after /review-code
    reason: projctl sync push returned non-zero (backup may be unavailable)
    recovery: run `projctl sync push` manually; also run `projctl sync status`
              before /complete to verify no drift has accumulated across machines
```

Do not fail this skill — return success after surfacing the warning.

## Review Scope

Each of the 3 agents evaluates:
- **Supportability:** Logging, error messages, debugging
- **Extendability:** Modularity, abstractions, future-proofing
- **Maintainability:** Code clarity, naming, complexity
- **Testability:** Unit tests, test coverage, edge cases
- **Performance:** No bottlenecks, efficient algorithms
- **Safety:** Error handling, resource management, thread safety
- **Security:** Input validation, no vulnerabilities
- **Observability:** Logging, metrics, tracing
- **Minimality:** Public API surface is no larger than required — flag multiple methods that share the same underlying resource, preconditions, and side effects where a single call with a discriminated return type would eliminate the risk of a caller silently skipping an action type
- **Design adherence:** Matches approved design
- **Standards compliance:** Coding standards and static analysis
- **Library reuse:** New classes/functions that duplicate functionality already available in the project's own common/utility code or in well-established ecosystem libraries (STL, Boost, OpenSSL, stdlib equivalents for each language). Flag custom implementations that should be replaced — prefer battle-tested library code over reinvention.

## Behavioral Bug Test Requirement

Any finding that identifies **incorrect runtime behavior** MUST include a `**Required test:**` line as part of the finding body. This applies regardless of severity.

**Incorrect runtime behavior** means the code:
- Produces wrong output or corrupts data (e.g., writes redirect response body into a download file)
- Silently accepts input that should be rejected (e.g., treats HTTP 3xx as success)
- Gets stuck or loops incorrectly (e.g., complete-file → 416 → infinite retry)
- Bypasses a stated security or correctness invariant

This does NOT apply to quality findings (naming, observability, performance, maintainability) that have no wrong-output consequence.

The `**Required test:**` line must describe the minimal test that would fail before the fix and pass after:
- What precondition / input triggers the bug
- What outcome the test asserts

## Output Format

Produce a markdown report:

```markdown
# Code Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature / PR title>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description...
  **Required test:** <what input triggers the bug and what the test asserts> *(only for behavioral bugs)*

### High
- **H1** [attribute] Description...
  **Required test:** <description> *(only for behavioral bugs)*

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Codex-Only Findings

Findings raised by Codex that did not reach 2/3 Claude consensus. Include even if 0 — write "None."

- **X1** [severity] Description...

## Library Reuse Findings

Findings where new code duplicates functionality from the project's own common/utility modules or from available ecosystem libraries. Reviewers MUST check:

- **Project-internal duplication** — new functions/classes that replicate logic already present in the project's shared utilities, base classes, or helper modules. Flag as `High` if the duplicated code handles correctness-critical logic (parsing, serialization, crypto, error propagation).
- **Ecosystem library substitution** — custom implementations of functionality covered by standard or widely-adopted libraries (e.g., hand-rolled base64 when OpenSSL/Boost.Beast/stdlib provides it; manual JSON parsing when a project-approved library exists; custom thread pool when `std::thread` / `concurrent.futures` / `goroutines` suffice). Flag as `Medium` unless the custom code is security-sensitive, in which case `High`.
- **Vendored or pinned library ignored** — the project already vendors or pins a library that covers the use case but the new code does not use it.

Severity guidance:
- `High` — duplication in security, crypto, parsing, or data-integrity paths; or ignoring an already-vendored library
- `Medium` — general algorithmic duplication that a standard library covers; minor helper reimplementation
- `Low` — style-level preference (e.g., using raw loops where a standard algorithm reads more clearly)

- **R1** [severity] Description...

## Common Library Promotion Candidates

Only include this section when a genuine candidate is found — do **not** add it as a template placeholder or write "None." Proposals driven by the template rather than by real evidence are noise and MUST be suppressed.

A candidate qualifies when it meets ALL of the following criteria:

- **Domain-neutral** — logic is not specific to one subproject's business rules; it solves a generic problem (data transformation, I/O, concurrency, protocol handling, validation, etc.)
- **Self-contained** — has few or no dependencies on subproject-local state, types, or configuration
- **Stable interface** — the public API is unlikely to churn as the subproject evolves
- **Broadly applicable** — at least two other subprojects would plausibly call this code today or in the near term

For each genuine candidate, provide:
```
**Candidate:** <function or class name>
**Location:** <file path and line range>
**Rationale:** <one sentence — what generic problem it solves>
**Reuse signal:** <list the subprojects or contexts that would benefit>
**Suggested home:** <proposed module/package path in the common library>
```

## Test Correctness Findings

Findings about test quality not already present in the consensus section. Focus on correctness gaps, not style.

Reviewers MUST check:
- **New code without dedicated test file** — for every new source unit (`.h`/`.cc` pair, standalone utility, or module) introduced in this PR, verify that a corresponding dedicated test file exists. Indirect exercise through a higher-level test suite is not sufficient — each unit needs its own tests. Flag as `High` if missing.
- **Missing failure scenarios** — public functions/methods that can fail but have no test for invalid input, dependency errors, or boundary violations. Flag each uncovered failure mode as a separate finding.
- **Vacuous assertions** — assertions that pass even when the implementation is wrong (e.g., only checking non-null, only checking call count without argument verification).
- **Name/assertion mismatch** — test name describes a scenario the assertions do not actually verify.
- **Under-specified error assertions** — error-path tests that only assert "an error occurred" without checking the error type, code, or message.

Severity guidance:
- `High` — missing failure-scenario test for a function that handles security, data integrity, or resource management
- `Medium` — missing failure-scenario test for non-critical paths; vacuous or mismatched assertions
- `Low` — under-specified error assertions where the type/message check would be easy to add

- **T1** [severity] Description...

## Recommendation
<rationale and required actions if not approved; reference findings by ID e.g. "Fix C1, H2 before proceeding">
```

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity (C1, C2, H1, H2, M1, …). IDs are stable within a review session and used when discussing or resolving findings.

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → proceed to `/verify`
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → redesign needed

## After Resolving CHANGES REQUESTED Findings

When a review returns CHANGES REQUESTED and fixes touch `docs/` or `planning/**/issues/*/` files:

1. Run `/verify-docs` on all modified files before requesting re-review.
2. Fix any blockers reported by `/verify-docs`.
3. Only then re-run `/review-code`.

## Next Step

After approval, use `/verify` to run tests and static analysis.
