---
name: implement
description: Implement approved design using coder or devops-engineer agent
---

# Implementation Command

Implement the approved design following the chosen agent's expertise.

## Agent Selection

- **coder** (sonnet): Application code (C++, Go, Rust, Python)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure

## Skills Required

- languages/* (language-specific guidelines)
- domains/code-quality (code quality standards)
- domains/testing (testing strategies)

## File Overwrite Convention

`/review-code` always writes a **single** file `code-review.md` inside the issue folder, overwriting any prior content. No versioning suffixes. The gate below reads from this single file. Git history preserves prior versions.

## Actions

### 0-pre. Gated auto-compact (first step — §7.3, §7.4)

Before doing anything else, evaluate two disk-checkable preconditions. Both must pass for compaction to fire.

**Precondition 1 — approved design on disk, aligned with review:**

```bash
# Locate the design and design-review files for this feature
DESIGN="planning/<goal>/milestone-XX/issues/<NNN-name>/design.md"
REVIEW="planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md"

# Check all four sub-conditions:
# a) design file exists
test -f "$DESIGN"
# b) design-review file exists
test -f "$REVIEW"
# c) review mtime >= design mtime (review was written after design)
test "$REVIEW" -nt "$DESIGN" || test "$REVIEW" -ef "$DESIGN"
# d) status marker is exactly APPROVED
DESIGN_STATE=$(head -20 "$REVIEW" | grep -m 1 '^\*\*Status:\*\*' | sed 's/^\*\*Status:\*\* //')
[ "$DESIGN_STATE" = "APPROVED" ]
# e) no unresolved on-device open questions in design doc Open Questions section
# If analysis.md '## On-Device Scope' is YES or YES-UNKNOWN, verify that the Open
# Questions section of design.md contains no open (unchecked) items mentioning on-device scope:
ANALYSIS="planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md"
if grep -q '## On-Device Scope' "$ANALYSIS" 2>/dev/null && grep -A1 '## On-Device Scope' "$ANALYSIS" | grep -qiE '^(YES|YES-UNKNOWN)'; then
    ! grep -iE 'on-device verification|device procedures' "$DESIGN" | grep -q '^\- \[ \]'
fi
```

All five sub-conditions must pass. If any fail, precondition 1 fails. For sub-condition (e), a matching unchecked item causes the gate to log `precondition-1-failed:unresolved-ondevice-open-question` and surface a warning directing the user to resolve the on-device scope open question before implementing.

**Precondition 2 — no open code-review cycle:**

```bash
CODE_REVIEW="planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md"

# Either the file does not exist (first /implement run for this feature):
if [ ! -f "$CODE_REVIEW" ]; then
    echo "pass"  # precondition 2 passes
else
    # Or the latest review's status is exactly APPROVED:
    CODE_STATE=$(head -20 "$CODE_REVIEW" | grep -m 1 '^\*\*Status:\*\*' | sed 's/^\*\*Status:\*\* //')
    [ "$CODE_STATE" = "APPROVED" ]
fi
```

**Cycle semantics summary:**
- First `/implement` (no code-review file): precondition 2 passes → compact.
- After `/review-code` writes `CHANGES REQUESTED`: precondition 2 fails → skip compact.
- After `/review-code` overwrites with `APPROVED`: precondition 2 passes → compact on any subsequent `/implement`.
- After `/review-code` writes `REJECTED`: precondition 2 fails → skip compact (`REJECTED` is not `APPROVED`).
- User re-invokes `/implement` after an `APPROVED` review ("tweak one thing"): precondition 2 passes → compact. Correct: the prior cycle is closed.

**If both preconditions pass:**
- Log to gate-decision log: append one line to `planning/.workflow-safety.log`:
  ```
  <ISO-8601 timestamp> /implement implement-begin FIRED
  ```
- Trigger compaction (automatic, no prompt per §7.8).
- After successful compaction, emit:
  ```
  ✓ Compacted at implement-begin (N messages summarized)
  ```
- **If compaction fails:** log `<ISO-8601 timestamp> /implement implement-begin SKIPPED compact-failed`, surface `⚠️  workflow-safety: compaction failed at implement-begin — proceeding normally`, and continue. Do not block the coder agent launch.

**If either precondition fails:**
- Log to gate-decision log:
  ```
  <ISO-8601 timestamp> /implement implement-begin SKIPPED <failing-precondition>
  ```
  Where `<failing-precondition>` is one of: `precondition-1-failed:design-missing`, `precondition-1-failed:review-missing`, `precondition-1-failed:mtime-order`, `precondition-1-failed:status-not-APPROVED`, `precondition-1-failed:unresolved-ondevice-open-question`, `precondition-2-failed:CHANGES_REQUESTED`, `precondition-2-failed:REJECTED`.
- Surface warning:
  ```
  ⚠️  workflow-safety: compaction skipped at /implement
      reason: <specific failing precondition>
      recovery: <appropriate action, e.g. "address findings and re-run /review-code to close the cycle">
  ```
- Do NOT compact. Continue with implementation normally.

### 0. Read skills for phase context:
   ```
   Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
   Read ~/.claude/skills/domains/code-quality/SKILL.md
   Read ~/.claude/skills/domains/testing/SKILL.md
   ```
   If using devops-engineer agent, also read:
   ```
   Read ~/.claude/skills/domains/devops/SKILL.md
   ```

1. Select appropriate agent based on task type
2. Write code following approved design
2a. **Check for on-device entry point deliverable:** First read `analysis.md ## On-Device Scope`. If scope is YES or YES-UNKNOWN, verify the design doc contains an `**Entry point:**` line — if it does not, abort with a workflow-safety warning: "On-device scope is YES but design doc is missing the On-Device Verification section; resolve before implementing." If the section is present, check whether the named script or Makefile target exists on disk:
   ```bash
   # Example (non-exhaustive — adapt to the entry point form named in the design doc):
   test -f scripts/verify-device.sh \
     || grep -q 'verify-device' Makefile \
     || grep -qE 'test-device|verify-device' dev.sh
   ```
   If it does not exist on disk, creating that entry point is a **mandatory deliverable** of this implementation. Pass the On-Device Verification excerpt from the design doc to the coder agent with explicit instruction to implement the entry point covering the documented build/deploy/verify steps. Do not skip or defer this — omitting it will be caught as High in `/review-code`.
3. Include comprehensive unit tests (mandatory):
   - Cover all public API paths
   - Cover edge cases: empty input, null/None, boundary values, error paths
   - **Cover behavioral correctness scenarios** — any path where incorrect runtime behavior is possible (wrong output, silent invalid-input acceptance, liveness violations, security bypass) requires an explicit test. See `~/.claude/skills/domains/testing/SKILL.md` → Behavioral Correctness.
4. Verify build passes after each change
5. Follow language-specific style guides:
   - C++: C++ Core Guidelines
   - Python: PEP 8, Google Python Style Guide
   - Go: Effective Go, Code Review Comments
   - Rust: Rust API Guidelines
   - Zig: Zig Style Guide
6. Apply code formatting (clang-format, black, rustfmt, etc.)

## Output

Implementation complete with:
- Production code
- Comprehensive unit tests
- Passing build
- Applied formatting

## Usage

```
"I'll use coder agent to implement the authentication module following the approved design..."
```

```
"I'll use devops-engineer agent to create the CI pipeline configuration..."
```

## Planning State Update (last step before handing off)

After implementation is complete and build passes, update planning state:

**Planning checkpoint** (`new_phase = code review ⏳`, `progress_line = - implementation complete — ready for /review-code`, `escalation = standard`):
```
Read ~/.claude/skills/workflows/planning-checkpoint/SKILL.md
```

## Next Step

**Next step:** Do not auto-invoke `/review-code`. Wait for the user to type `/review-code` or an equivalent explicit directive. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization — see CLAUDE.md Critical Rules for the two-part test.
