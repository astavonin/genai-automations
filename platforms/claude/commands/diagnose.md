---
name: diagnose
description: Investigate a failure or unexpected behavior using the debugger agent + Codex cross-model verification. Produces a root cause diagnosis and fix recommendation.
---

# Diagnose Command

Investigate a failure using the **debugger (opus)** agent and **Codex** as an independent cross-model verifier.

## Agent

**debugger** (opus model)

## Input

The user provides a failure description, e.g.:
```
/diagnose ci job failing with "VERSION_NUMBER: unbound variable"
/diagnose build.sh crashes when DOCKER_IMAGE_VERSION is local:latest on CI
/diagnose unit test flaky — passes locally, fails in pipeline
```

Optionally attach: log output, stack trace, error message, or relevant file paths.

## Setup

Every failure reaching this command already happened, so the observed-failure regression rule applies to whatever fix comes out of it:

```
Read ~/.claude/skills/workflows/regression-test/SKILL.md
```

## Workflow

### Step 1: Claude Debugger Investigation

Invoke the **debugger** agent with:
- Full failure description and any provided logs/traces
- Relevant project context (current working directory, recent changes)
- Instruction to follow the 7-phase process and produce the standard output format, **including the mandatory Regression Test section** (Phase 7)

### Step 2: Codex Cross-Model Verification

After the Claude debugger produces its diagnosis, run Codex independently:

```bash
~/.claude/scripts/codex-pipe \
  --prompt "Debug this failure. Identify root cause, propose a fix, and specify the regression test (unit or integration, with test file, precondition, and assertion) that would catch this failure if it returns:\n\n<failure description and context>" \
  --output /tmp/codex-diagnose.txt \
  <relevant-file-if-applicable>
```

Or for log-based failures (no separate file — embed log and code in the prompt):
```bash
~/.claude/scripts/codex-pipe \
  --prompt "Root cause analysis:\n\n<error log>\n\nRelevant code:\n\n$(cat <file>)" \
  --output /tmp/codex-diagnose.txt
```

Run from the project's working directory.

### Step 3: Cross-Aggregate Results

Compare Claude debugger diagnosis with Codex proposal:

| Result | Action |
|--------|--------|
| Both agree on root cause | High confidence — present as confirmed |
| Both agree on fix approach | Mark fix as **✓ Corroborated by Codex** |
| Claude-only diagnosis | Present with confidence level noted |
| Codex-only finding | Present separately as **"Codex alternative hypothesis"** — different model, worth considering |
| Disagree on root cause | Present both hypotheses with supporting evidence — let user decide |
| Differ on regression test level (unit vs integration) | Prefer the integration specification — see the selection table in the regression-test fragment |

### Step 4: Present Diagnosis

Output to the user:
- **Root cause** (with confidence: confirmed / likely / hypothesis)
- **Fix recommendation** (with corroboration status)
- **Regression test** (mandatory) — level, test file, precondition, assertion, and name, taken from the debugger's Phase 7 output and reconciled with Codex's proposal. If the debugger flagged a waiver candidate, present the category and the proposed compensating control, and state plainly that a waiver needs the user's explicit approval.
- **Codex alternative** (if different)
- **Next step**: hand off to `/implement` (coder agent) or `/verify` as appropriate

### Step 5: Record the Failure in the Ledger (mandatory)

The gate downstream reads a file, not this conversation — sessions compact and `/verify` may run days later. First resolve where the file goes:

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

Resolve `<issue-folder>` by that procedure (including the orphan fallback for unlinked fixes) and echo the resolved path. Then append one entry per root cause to `<issue-folder>/observed-failures.md`, creating the file and its orphan folder if absent, using the entry format in the regression-test fragment:
- Fill `Observed in`, `Root cause`, and `Test` from the Regression Test specification
- Write `**Status:** open` — the entry is recorded, not yet resolved. `/implement` replaces this line when the fix lands. Do not copy the template's `<open | covered | ...>` placeholder literally.
- **Check the root cause against this work before writing the entry.** If it belongs to different work — another issue, or a later step of the same rollout — name that owner in the entry as `**Belongs to:** <work>` and tell the user in one line. Still write the entry: the four statuses have no value meaning "someone else's", and dropping the entry loses a real failure, which is worse than the wrong ledger holding it. The `/verify` gate will block on it, and naming the owner is what lets the user move or waive it instead of overriding by hand. This has already happened once — a step-2 ledger took a step-5 root cause, `/verify` blocked, and the disposition was written by hand with no waiver category.

Then push the ledger to backup so it survives a machine switch — a ledger that exists only locally cannot anchor a gate that fires days later:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

### Step 6: Carry the Test into the Handoff

The regression test is part of the fix, not a follow-up. When handing off:
- Pass the full Regression Test specification to `/implement` alongside the fix recommendation
- State explicitly that the fix and the test are one deliverable — `/verify` blocks on an unresolved ledger entry
- Do not file the test as a separate ticket, TODO, or "nice to have later"

## Notes

- The diagnose command investigates — it does NOT implement fixes or write the test
- After diagnosis, use `/implement` to apply the fix **and** the specified regression test
- For CI/CD-specific failures, prefer `/ci-debug` which has pipeline-specific tooling
- Re-running `/diagnose` on the same issue after a failed fix attempt is expected and encouraged. When this happens, check whether the earlier fix shipped a regression test — a recurrence that a prior test should have caught means the test asserted a proxy rather than the real symptom, and fixing the test is part of this round's work.
