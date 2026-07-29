# Code Review Workflow

The request document is a review request.

Execution contract:
- `Repository`
- `Review Scope`
- `Output File`
- `Requirements`
- `Constraints`
- `Observed-Failure Ledger`
- `Evidence`
- `Review Focus`

Findings are the primary output. Requirement coverage and verification gaps must be explicit.

## Observed-Failure Regression Pass (mandatory)

*Mirrors `~/.claude/skills/workflows/regression-test/SKILL.md` → Review Severities, which is authoritative. This is the only copy that reaches `codex-flow review`, which runs with `--ignore-user-config`; keep it in step with the source.*

Determine whether the change fixes a failure that **actually happened** — a red CI job, an on-device or deployment failure, a runtime crash or hang, a manual-testing defect, a bug report, a flaky test, or a review finding confirmed to reproduce. If it does, the fix and a test reproducing that failure are one deliverable; a fix alone is incomplete.

Read the request's `Observed-Failure Ledger` section and judge each entry by its `**Status:**`:

- `covered` — resolved. Verify the named test asserts the **actual observed symptom** rather than a proxy, and that its level matches the failure. Composition failures (env vars, startup order, config load, component interaction, CI structure) need integration coverage; a unit test that mocks the exact boundary the bug crossed re-encodes the bug's assumption and does not count.
- `waived` — resolved. A recorded, user-approved waiver is a **valid outcome**; do not report it as a missing test. Flag it only when its stated category plainly does not hold or no compensating control is named.
- `out-of-scope` — resolved, unless the stated reason plainly does not hold.
- `open` — **not** resolved. Report as High.

Report as High: an observed failure with no ledger entry; an `open` entry; an entry carrying two `**Status:**` lines or none (a malformed entry is not a resolved one); a test that asserts a proxy rather than the symptom; a unit test mocking the boundary that *is* the root cause; an invalid waiver or out-of-scope reason. Report as Medium: a unit test mocking a crossed boundary that is not the root cause; a `covered` entry with no evidence of the test failing before the fix.

A green re-run is not a regression test — "CI passes now" proves the fix worked once, not that the failure is guarded.

**Exception — external merge requests.** When the ledger section states that no ledger exists because the MR is external, the ledger convention does not apply to that author. Raise a missing regression test as a **question**, never as a High blocker citing a ledger or waiver they have no mechanism to record. In every other case an absent ledger is not an exemption: if the scope shows evidence of an observed failure (a bug-ticket reference, a `fix:`/`hotfix` branch or commit, a CI-config or script change following a red pipeline), the missing entry is itself the defect.
