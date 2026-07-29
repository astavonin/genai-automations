---
name: regression-test
description: Shared fragment — single source of truth for the observed-failure regression rule. Defines what counts as an observed failure, the on-disk ledger that anchors the gate, unit-vs-integration selection, red/green evidence, review severities, and the waiver escape hatch. Read directly by diagnose, ci-debug, implement, verify, refresh, start, review-code, review-fix, review-code-fix-loop, review-iterate, and the coder/devops-engineer/debugger agents; reached indirectly by review-mr and the reviewer agent via review-checklist.md Test Quality Pass Step 3.
allowed-tools: Bash, Glob, Grep, Read
compatibility: claude-code
metadata:
  version: 2.0.0
  category: workflows
  tags: [workflow, testing, regression, debugging, gate]
---

# Observed-Failure Regression Test — Shared Fragment

**This file is the single source of truth for this rule.** Other files reference the sections below; they do not restate them. If you are editing a trigger, a severity, or the selection table, edit it here.

## Rule

Every **observed failure** produces two deliverables, not one: the fix, and a test that reproduces the failure. A fix without a covering test is incomplete work — not eligible for `/verify` completion, `/complete`, or review approval.

This is a hard gate. The only alternative to writing the test is a **user-approved recorded waiver**. Shipping a fix for an observed failure with no test and no waiver is never permitted, regardless of how obvious, small, or "clearly correct" the fix looks.

**A green re-run is not the regression test.** "CI passes now", "the device works now", "I ran it and it's fine" prove the fix worked once. They do not prove the failure is guarded. Only a test that asserts the specific symptom closes the gate.

## What Counts as an Observed Failure

*Do not copy this list — link to it. Consumers reach it either by reading this fragment directly or, for reviewer agents, through `review-checklist.md` → Test Quality Pass Step 3.*

A failure that **actually happened** in a real execution, as opposed to one anticipated during design:

1. A job failed in CI — test, lint, build, deploy, or pipeline structure
2. A failure, crash, hang, or wrong behaviour observed on a device or in a real deployment
3. A defect found by manual testing, exploratory use, or a bug report
4. A flaky or intermittent test — the flake itself is the observed failure
5. Anything routed through `/diagnose` or `/ci-debug`
6. A review finding describing incorrect runtime behaviour that was **confirmed to reproduce** — including findings fixed inside `/review-code-fix-loop` and `/review-iterate`

If the failure is anticipated rather than observed, this fragment does not apply — `~/.claude/skills/domains/testing/SKILL.md` → Failure Scenario Coverage governs instead. Both can apply to the same change.

### Out of Scope

- **No repository component** — runner offline, registry unreachable, expired token, upstream service down, and nothing in the repo changes. Record the failure in the ledger with `**Status:** out-of-scope` and a one-line reason rather than leaving the gate unaddressed.
- **Nothing assertable changed** — a yanked dependency or action version bumped to a working one, a `.gitignore` correction, a docs-only fix for a broken link. The decidable test is *"does the fix change behaviour the repository can assert on?"* — not *"does it feel like an infra problem?"* A CI YAML, Dockerfile, or shell script edit that changes behaviour **is** in scope. Record these as `**Status:** out-of-scope` with the reason.

- **Analysed, did not reproduce** — a reported failure (most often a review finding, trigger 6, but any trigger can be mistaken) that investigation showed cannot actually occur, because an upstream guard already prevents it or the reasoning behind the finding was wrong. Record `**Status:** out-of-scope` with `**Reason:** review finding <ID> — analysed, does not reproduce: <why>`. Trigger 6 fires on findings *confirmed to reproduce*; without this clause a correctly-refuted finding would have no representable outcome and reviewers would raise an unclearable High against it.

A review finding about naming, comments, formatting, or observability polish is not an observed failure at all — it never enters this fragment. Do not use "quality finding" as an exit from a failure that actually occurred.

## The Ledger (on-disk anchor)

The gate must not depend on remembering that a failure happened. Sessions compact, work spans days, and `/verify` frequently runs in a context where the original CI log is long gone. **The trigger is a file, not a memory.**

**Path:** `<issue-folder>/observed-failures.md`. Resolve `<issue-folder>` — including the orphan fallback for unlinked fixes — with:

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

Resolve it **before** the first read or write, and pass the resolved string to any command you hand off to. A writer and a reader that derive the path differently miss each other silently: an absent ledger reads as "nothing to do", not as an error.

**Who writes it:** `/diagnose` and `/ci-debug` create or append an entry per root cause at diagnosis time, with `**Status:** open`. `/implement` and `/codex-implement` resolve each entry when the fix lands. `/review-code-fix-loop` and `/review-iterate` append an entry for every finding confirmed to reproduce. **`/verify` and `/review-fix` write the `waived` and `out-of-scope` resolutions** once the user has approved one — the command that surfaced the blocker owns closing it, or an approved waiver is re-litigated on every subsequent run. Writing that resolution is a ledger edit, not a planning-state update, so it is not covered by a "do not update planning state" hold.

**Append-only at entry granularity.** Never delete or consolidate an existing `##` section, and never let a second failure inherit the first entry's resolution — each gets its own entry. Fields **within** an entry are edited in place: `/implement` replaces the `**Status:** open` line rather than appending a second Status line. **Exactly one `**Status:**` line per entry** — two is a malformed entry, not a resolved one. This file is exempt from the "one final published output" convention, which governs review reports, not ledgers.

**Entry format:**

```markdown
# Observed Failures — <issue or fix name>

## <YYYY-MM-DD> <one-line symptom>
**Observed in:** <CI job `test:unit` pipeline 456789 | on device <name> | manual testing | bug report | review finding H3>
**Root cause:** <one line>
**Status:** <open | covered | waived | out-of-scope>
**Test:** `tests/integration/test_deploy.py::test_deploy_fails_fast_on_unset_version` (integration)
**Evidence:** before fix FAIL — "VERSION_NUMBER: unbound variable"; after fix PASS
```

`open` is the initial state when a failure is recorded *before* it is fixed — the `/diagnose` and `/ci-debug` path. An entry created after the fix already landed may be written directly as `covered`; do not write `open` and then append a second Status line, which is the malformed shape the gate rates High. The other three states are terminal. An entry is **resolved** when its status is `covered`, `waived`, or `out-of-scope`; `open` never satisfies the gate.

For `**Status:** waived`, replace the `Test` and `Evidence` lines with:

```markdown
**Waiver category:** <1 unavailable-environment | 2 harness-defect | 3 destructive-reproduction | 4 non-deterministic-race | 5 workflow-instruction-defect>
**Approved by:** <user>, on <YYYY-MM-DD>
**Compensating control:** <runtime assertion, invariant check, log + alert, config validator, monitoring rule, or runbook entry>
```

For `**Status:** out-of-scope`, replace them with `**Reason:** <which out-of-scope clause applies and why>`.

A **CI-level guard** — a config validator, lint rule, or smoke job that makes the pipeline fail on regression — is a valid `**Test:**` value when the pipeline's own structure was at fault. Name the job and what makes it fail.

## Test Level Selection

*Referenced by: everywhere. Do not paraphrase this table — link to it.*

**Default to integration.** Observed failures are usually composition failures — the units worked, their interaction did not. A unit test that mocks the exact boundary the bug crossed re-encodes the bug's assumption instead of catching it.

| The observed failure was reproducible from… | Test level |
|---|---|
| Pure logic with the inputs in hand (parse, compute, validate, branch) | Unit |
| Two or more real components interacting (DB, HTTP, broker, IPC, filesystem) | Integration |
| Process or environment composition (env vars, startup order, config load, CLI arg wiring, unbound variable in a script) | Integration |
| CI pipeline structure itself (job ordering, cache keys, image tag, build flags) | Integration, plus a CI-level guard so the pipeline fails on regression |
| Device or hardware interaction | Integration against the on-device entry point named in the design doc |

When unsure, write the integration test. An unnecessary integration test costs seconds of runtime; a missing one costs the same failure a second time.

Tag integration tests to run separately per `~/.claude/skills/domains/testing/SKILL.md` → Integration Testing.

**Inline-test languages:** Rust (`#[cfg(test)] mod tests`) and Zig (`test "..." {}`) put unit tests in the source file under test. There is no separate test path for these — record the test's module and name in the ledger's `**Test:**` field.

## Red/Green Evidence (required, best-effort)

Write the test **before** applying the fix and confirm it reproduces the failure:

1. Write the test against the **unfixed** code
2. Run it — it must **fail**, and fail for the observed reason (assert on the actual symptom, not a proxy)
3. Apply the fix
4. Run it — it must **pass**
5. Record both outcomes in the ledger's `**Evidence:**` field

**When red/green is impracticable** (reverting would require re-flashing a device, destroying shared state, or waiting on a non-deterministic race), say so plainly instead of fabricating it:

```markdown
**Evidence:** before-fix state not demonstrated — reverting requires re-flashing the device.
Falsifiability: the assertion targets <symptom>; it cannot pass unless <fixed behaviour> holds.
```

Never record a red/green result that was not actually observed. An undemonstrated test needs the falsifiability argument in its place.

## Test Naming

Name the test after the **behaviour and expected outcome**, per `~/.claude/skills/domains/testing/SKILL.md` → Test Naming. Never after the incident, ticket, finding, or fix round:

- Good: `test_deploy_fails_fast_on_unset_version`, `test_download_rejects_redirect_response_body`
- Bad: `test_ci_fix`, `test_issue_42_regression`, `test_fix_for_finding_h3`, `test_regression_1`

The test is a permanent statement of required behaviour. The incident belongs in the ledger, not in the test name. See `~/.claude/agents/coder.md` → the rule against referencing review findings in test names.

## Hard Gate

The ledger is the gate. **Set `ISSUE_FOLDER` to the path you resolved** (see The Ledger above), then run the rest unchanged. The variable is deliberately left empty below so the guard fires if you forget — do not replace it with a placeholder string, or the gate will report a confident `N/A` for a ledger that exists.

```bash
ISSUE_FOLDER=""     # <-- fill in the resolved path, e.g. planning/foo/milestone-02-bar/issues/014-baz
LEDGER="${ISSUE_FOLDER:?resolve the issue folder first — see issue-folder-resolve/SKILL.md}/observed-failures.md"
case "$LEDGER" in *"<"*) echo "BLOCKER: placeholder left in path — $LEDGER"; exit 1;; esac

echo "ledger: $LEDGER"
if [ ! -f "$LEDGER" ]; then
    echo "N/A: no ledger at that path — confirm the path is right before trusting this"
    exit 1   # not a pass: no caller may read a missing ledger as success
else
    awk '
      /^## /        { rawHeads++ }                   # counted before the fence filter
      /^(```|~~~)/  { fence = !fence; next }        # ignore fenced content
      fence         { next }
      /^## /        { if (seen) report(); seen = 1; head = substr($0, 4); n = 0
                      st = ""; hasTest = hasCat = hasAppr = hasCtrl = hasWhy = 0 }
      /^\*\*Status:\*\* *(covered|waived|out-of-scope) *$/ { n++; st = $2; next }
      /^\*\*Status:\*\* *open *$/                          { n += 100;     next }
      /^\*\*Status:\*\*/                                   { n += 10000;   next }
      /^\*\*Test:\*\* *[^ ]/                 { hasTest = 1 }
      /^\*\*Waiver category:\*\* *[1-5]/     { hasCat  = 1 }
      /^\*\*Approved by:\*\* *[^ <]/         { hasAppr = 1 }
      /^\*\*Compensating control:\*\* *[^ ]/ { hasCtrl = 1 }
      /^\*\*Reason:\*\* *[^ ]/               { hasWhy  = 1 }
      END { if (seen) report()
            if (fence) { bad++; print "BLOCKER: unclosed code fence — entries after it were NOT scanned" }
            # An even number of stray fences re-balances, so the EOF check above cannot see it —
            # yet everything between the pair is invisible. Compare headings counted before the
            # fence filter against entries actually scanned.
            if (rawHeads != total) { bad++
              printf "BLOCKER: %d entry heading(s) hidden inside a code fence — indent pasted output four spaces instead of fencing it\n", rawHeads - total }
            if (total == 0) print "BLOCKER: ledger exists but records no entries"
            else if (bad == 0) printf "PASS: %d observed failure(s) resolved\n", total
            exit (bad || total == 0) ? 1 : 0 }
      function report(  terminal, opens) {
        total++
        # A resolution is only as good as the fields justifying it. Without this a bare
        # "**Status:** waived" would pass — the one escape from a hard gate, unjustified.
        if (st == "covered"      && !hasTest) { bad++; printf "BLOCKER: covered but no Test: field — %s\n", head }
        if (st == "waived"       && !hasCat)  { bad++; printf "BLOCKER: waived but no Waiver category: 1-5 — %s\n", head }
        if (st == "waived"       && !hasAppr) { bad++; printf "BLOCKER: waived but no Approved by: — the user approves, you may not — %s\n", head }
        if (st == "waived"       && !hasCtrl) { bad++; printf "BLOCKER: waived but no Compensating control: — %s\n", head }
        if (st == "out-of-scope" && !hasWhy)  { bad++; printf "BLOCKER: out-of-scope but no Reason: — %s\n", head }
        if (n == 1) return
        bad++
        terminal = n % 100; opens = int((n % 10000) / 100)
        if (n >= 10000)              printf "BLOCKER: unrecognized Status value (use open|covered|waived|out-of-scope) — %s\n", head
        else if (terminal + opens > 1) printf "BLOCKER: %d Status lines (malformed — keep one, edit in place) — %s\n", terminal + opens, head
        else if (opens == 1)         printf "BLOCKER: still open — %s\n", head
        else                         printf "BLOCKER: no Status line — %s\n", head
      }
    ' "$LEDGER"
fi
```

It reports **each unresolved entry by name** rather than a count, so the output says what to go fix. Three properties are load-bearing:

- **Per-entry counting.** A file-wide tally lets one entry carrying two `Status` lines mask a neighbouring entry that has none.
- **The EOF fence check.** An unbalanced fence — an unclosed block, or an `Evidence` block whose pasted output itself contains a ` ``` ` or `~~~` line — makes every later line invisible, including `## ` headings and `Status: open`. Without the check that prints `PASS`. Since the ledger is append-only, one bad fence would disable the gate for everything appended afterwards.
- **The unrecognized-value catch-all.** `Covered`, `waived (pending approval)`, a tab after the colon, or CRLF line endings would otherwise report as "no Status line", inviting an agent to *add* a second one and create a malformed entry.

When pasting command output into an `Evidence` field, indent it four spaces instead of fencing it.

**`N/A` is not automatically a pass.** It proves only that no file was found at the path printed on the `ledger:` line. First confirm that path is the one the writer used — a resolution mismatch and a genuinely absent ledger look identical here. If the path is right and nothing was recorded, ask directly: did anything fail during this work that a test does not now guard? If so, the missing entry *is* the defect — write it, resolve it, and re-run.

**A `PASS` is mechanical, not sufficient.** It confirms every entry has a status, not that the tests are real. Judgement still applies:
- The test asserts the **actual observed symptom**, not a proxy or an adjacent happy path
- The level matches the selection table
- Evidence is recorded, or a falsifiability argument replaces it
- **It would have caught the failure that was just diagnosed** — if the honest answer is no, the gate is not met

## Review Severities

*Single source for all review commands. Do not restate these mappings — link here.*

*Every downstream copy is listed below: three carry the severities, the fourth defers. Edit here first, then update all three carriers — a severity that disagrees across copies makes Claude and Codex reach different verdicts inside the same review.*

| Mirror | Why it exists |
|---|---|
| `~/.claude/skills/domains/quality-attributes/references/review-checklist.md` → Test Quality Pass Step 3 | verbatim copy; the one passed inline to reviewer agents |
| `~/projects/genai-automations/tools/codex-flow/codex_flow/resources/skills/workflows/code-review/SKILL.md` | prose form; the **only** copy that reaches `codex-flow review`, which runs with `--ignore-user-config` |
| `~/.codex/CODEX.md` → mandatory failure pass 4 | prose form; the severity list for interactive Codex sessions |
| `~/.codex/skills/domains/code-quality/references/code-review-checklist.md` | prose form; defers to CODEX.md pass 4 for severities |

| Condition | Severity |
|---|---|
| Observed failure with no ledger entry | High |
| Ledger entry still `Status: open` (no test, no waiver) | High |
| Ledger entry with two `Status:` lines, or none | High |
| Test present but asserts a proxy rather than the observed symptom | High |
| Unit test mocking the boundary the bug crossed, and that boundary **is** the root cause | High |
| Unit test mocking a boundary the bug crossed that is not the root cause | Medium |
| Waiver whose category does not hold, or with no compensating control | High |
| `Status: out-of-scope` whose stated reason does not hold | High |
| Evidence field missing on a `covered` entry | Medium |

**In `/review-fix`, every finding in this table is High** regardless of the default above — a fix review's entire subject is one observed failure, so a Medium here would approve the exact gap the review exists to catch.

**In `/review-mr`** (external MRs we do not own), there is no issue folder and no ledger. Raise a missing regression test as a **question to the author**, not a blocker, and never cite the waiver clause — the author has no mechanism to satisfy it.

## Waiver

A waiver is the only alternative to writing the test. It requires **explicit user approval**.

**Approval test:** the user must give a user-initiated directive naming the waiver, or explicitly approve a named category when asked. Assent to an assistant-proposed waiver — "ok", "sure", "go ahead" — is **not** approval; apply the two-part test from `~/.claude/CLAUDE.md` → Critical Rules. Never self-waive, and never fill in `**Approved by:**` from your own judgement.

**Allowed categories** (a waiver outside these five is not valid):

1. **Unavailable environment** — not reproducible without hardware or a third-party environment the project has no access to, and no fake, simulator, or recorded fixture can be built at proportionate cost
2. **Harness or provider defect** — the failure is in the test framework or CI provider itself, outside repository control
3. **Destructive reproduction** — reproducing requires an irreversible or destructive action against a shared or production resource
4. **Non-deterministic race** — a timing or hardware race with no deterministic reproduction, mitigated by an invariant check or assertion instead
5. **Workflow-instruction defect** — the failing component is a Markdown instruction an agent follows, not code, and the repository has no harness that executes workflow steps. Categories 1–4 all assume the untestable thing is code; this repo's dominant failure class is not. A waiver here still requires a compensating control that makes the failure *visible* — an explicit check the instruction mandates, a field in a published artifact, or a sweep that surfaces it later — because "an agent will follow the corrected instruction" is an expectation, not a control.

Every waiver requires a **compensating control**. A waiver that only explains why testing is hard is not acceptable — at minimum, the failure must become loud rather than silent.

Waivers are reviewable. `/review-fix` and `/review-code` validate each one; a waiver whose category does not hold returns that entry to "test required".

### Flaky Tests

A flake is an observed failure (trigger 4). `~/.claude/skills/domains/testing/SKILL.md` says to delete flaky tests immediately — **deleting the flaky test does not discharge this gate.** The two rules compose: delete the non-deterministic test, then either add a deterministic test of the underlying race, or record a category-4 waiver whose compensating control is an invariant assertion. Removing the symptom without addressing the race leaves the gate open.
