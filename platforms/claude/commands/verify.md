---
name: verify
description: Run linters, tests, and static analysis
---

# Verification Command

Run comprehensive verification before considering work complete.

## Setup

Read testing skill before starting:
```
Read ~/.claude/skills/domains/testing/SKILL.md
```

## Actions (Execute in Order)

1. **Run linters FIRST** (must pass before tests):

   **Linter Discovery Process:**
   a. Search for project linters in order:
      - Virtual environment (`.venv/bin/`, `venv/bin/`)
      - Project-local installations (`node_modules/.bin/`)
      - System PATH
   b. If linters not found, search for formatters:
      - Python: `black`, `autopep8`, `yapf`
      - C++: `clang-format`
      - Go: `gofmt`
      - Rust: `rustfmt`
   c. If neither linters nor formatters found:
      - **STOP** and explicitly ask user how to proceed
      - Provide options: install linters, skip linting, use basic syntax check
      - **DO NOT** proceed to tests without user decision
   d. **Prefer the comment rules where the repo already configures them.** Step 9 measures the ratio; these catch the classes a ratio cannot see. Where the repo's own linter config already carries the linter, prefer `ruff`'s `D` rules (declarations documented) and `ERA001` (commented-out code) for Python, `revive`'s `exported` rule for Go, and `missing_docs` for Rust, and report which of them the repo leaves off. This command ships no linter configuration into the repo under verification and does not add one.

   **Language-Specific Linters:**
   - Python: `pylint`, `flake8`, `mypy` (type checking)
   - C++: `clang-tidy`, `cppcheck` (via project build system, e.g. `./dev.sh lint --cpp`)
   - Go: `golangci-lint`, `go vet`
   - Rust: `clippy`
   - Shell: `shellcheck`

   **CRITICAL:**
   - Fix ALL linter errors and warnings before proceeding
   - If linters missing, this is a FAILURE - do not silently fall back to syntax checking

2. **C++ clangd analysis** (C++ projects only — skip for other languages):

   Clangd provides code intelligence from the editor's language server and catches
   issues that clang-tidy may miss (dead code, type mismatches, missing implementations).
   It complements the Docker-based linter — it does not replace it.

   **Step 2a — Identify changed C++ files:**
   ```bash
   # Uncommitted work:
   git diff --name-only HEAD | grep -E '\.(cc|cpp|h|hpp)$'

   # The whole branch — resolve the base, never hardcode it (see step 8):
   BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
     || BASE=$(git remote show origin | sed -n 's/.*HEAD branch: /origin\//p')
   git diff --name-only "${BASE:?could not resolve the default branch}"...HEAD \
     | grep -E '\.(cc|cpp|h|hpp)$'
   ```

   An empty list here means *no C++ files changed* — never *the diff failed*. `git diff` against a nonexistent ref aborts to stderr and leaves stdout empty, which is indistinguishable from a clean result once it reaches `grep`. If the base cannot be resolved, say so and scan uncommitted work only; do not record the Requirements bullet as satisfied against an empty list you did not verify.

   **Step 2b — Enumerate symbols in each changed `.cc` / `.cpp` file:**
   For each changed implementation file, use the LSP tool:
   ```
   LSP(operation="documentSymbol", filePath="<abs-path>", line=1, character=1)
   ```
   Review the returned symbol list:
   - Every method declared in the corresponding `.h` should appear
   - Flag any declared method with no matching symbol (missing implementation)
   - Flag any unexpectedly short method (< 3 lines) — use `hover` to verify its return type

   **Step 2c — Spot-check suspicious method bodies with hover:**
   For any method whose implementation looks incorrect (wrong return type, suspicious
   boolean expression, missing side effect), use:
   ```
   LSP(operation="hover", filePath="<abs-path>", line=<method-line>, character=<col>)
   ```
   This surfaces the inferred type at that position and can catch operator-precedence
   bugs and implicit conversions (e.g. `return !ptr != nullptr || arg == nullptr`
   returning `bool` when the intent was to store and start a worker).

   **Step 2d — Check for dead public API (optional, for smaller files):**
   For key public methods on core classes, use:
   ```
   LSP(operation="findReferences", filePath="<abs-path>", line=<method-line>, character=<col>)
   ```
   A public method with zero references is a candidate for removal or may indicate
   a caller was accidentally deleted.

   **Clangd limitations to be aware of:**
   - If `compile_commands.json` uses Docker-internal paths (e.g. `/workspace`), system
     headers (`zmq.h`, capnp headers) won't resolve on the host → ignore
     `file not found` diagnostics for those headers, they are environment false positives
   - Clangd diagnostics for local project headers and standard library types ARE reliable
   - `<new-diagnostics>` system reminders surfaced by the Edit tool are clangd output —
     review them, but filter out false positives from missing system headers

3. **Run all unit tests:**
   - Execute full test suite
   - Verify all tests pass
   - If no suite is discovered, say so on its own line and mark the Requirements bullet `not run` — never `✅`

4. **Run integration tests** (if applicable):
   - Execute integration test suite
   - Verify system integration
   - "If applicable" means a suite exists and is separable; where none is, report `integration: none discovered` rather than leaving it unmentioned

5. **Run static analysis:**
   - Additional static analysis tools beyond linters
   - Security scanners (if configured)
   - Code complexity analysis (if applicable)
   - Same rule as step 3: nothing discovered is `not run`, reported, not a silent `✅`

6. **Verify no regressions:**
   - Check existing functionality still works
   - Verify no breaking changes

   **Observed-failure regression coverage (HARD GATE).** Run this whole block; a mechanical `PASS` on the first sub-step does not end it.

   ```
   Read ~/.claude/skills/workflows/regression-test/SKILL.md
   ```

   **Step 6a — Resolve the issue folder, then run the ledger gate.**

   ```
   Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
   ```

   Resolve `<issue-folder>` by that procedure and assign the **resolved** path to `ISSUE_FOLDER` before running the fragment's Hard Gate snippet. Do not run the snippet with the placeholder still in it. It guards two ways — an unset or empty `ISSUE_FOLDER` aborts on `${ISSUE_FOLDER:?}`, and a `<...>` placeholder prints `BLOCKER: placeholder left in path` — and **an aborted gate is not a gate that ran**: resolve the path and run it again. Then check the `ledger:` line the snippet echoes and confirm it is the path `/diagnose` or `/ci-debug` wrote to — use Step 6b's `find` for that confirmation, unconditionally, not only on `N/A`: a `PASS` against the wrong folder reports another issue's entries as this one's verdict. If the resolve fragment bails (it tells commands that do not own the issue lifecycle to bail with an actionable error, and `/verify` is one), report `observed-failure gate: not run — issue folder unresolved` and treat the run as incomplete; do not continue as though the gate passed.

   **Step 6b — Handle an `N/A` result.** `N/A` means no file was found at the path printed above — which is a resolution mismatch as often as a genuine absence. Rule that out mechanically before believing it: run `find "$(git rev-parse --show-toplevel)/planning" -name observed-failures.md`. Adopt a hit **only if its path corroborates this work's identity** (the issue number, or the orphan slug) — a ledger belonging to different work is not yours, and binding to it would report another issue's entries as this one's verdict. If a corroborating ledger exists, re-run Step 6a against it; otherwise the `N/A` stands and you continue below. Then ask explicitly: **did anything fail during this work that a test does not now guard?** Consult the fragment's What Counts as an Observed Failure list; do not work from memory of it. If the answer is yes, the missing ledger entry is itself the defect: write it, resolve it, and re-run Step 6a. Only a genuine no lets you continue — record it as a one-line note in the `/verify` output and in the `progress.md` entry written by the Planning State Update step below.

   **Step 6c — Verify each resolved entry is real, not just marked.** A `PASS` confirms every entry carries exactly one terminal status, not that the work behind it happened. Check **every** resolved entry, every run — there is no on-disk record of what a previous `/verify` confirmed, so "already checked" is a memory claim and this gate exists precisely to not depend on one. Ledgers hold a handful of short entries; the cost is trivial. For each `covered` entry confirm all five:
   - The test asserts the **actual observed symptom**, not a proxy or a nearby happy path
   - Its level matches the fragment's selection table — a unit test mocking the exact boundary the bug crossed does not count
   - The `**Evidence:**` field records red/green, or carries a falsifiability argument where red/green was impracticable
   - It would have caught the failure that was diagnosed
   - **The file named in `**Test:**` still exists** — `test -f` it, or grep the test name. Nothing else checks this, so a fix that reverts an earlier fix and deletes its test leaves that entry reading `covered` forever. When coverage is genuinely withdrawn, re-resolve it through the closed list named in `### Out of Scope` of `~/.claude/skills/workflows/regression-test/SKILL.md`, in this order. A test that only moved or was renamed is not withdrawn: update the **Test:** field and stop. A test deleted with the behaviour it asserted is *Nothing assertable changed*, one whose remaining coverage would exercise only a dependency is *Third-party behaviour only*, and this run owns both — record the clause in place. A test deleted as vacuous is a category-6 waiver the user approves and this command or `/review-fix` records. Where nothing else resolves it, name the withdrawn test in `**Evidence:**` — planning is gitignored, so blanking is otherwise the last of it — then blank the **Test:** field and re-run the Step 6a gate, so the awk prints `BLOCKER: covered but no Test: field` inside the same run and Step 6d blocks that run. The entry then owes a live test from the issue's next `/implement`. That blocker kind is one Step 6d already lists — no new row, no fifth status, and the terminal-states sentence in `~/.claude/skills/workflows/regression-test/SKILL.md` stands unamended. Append-only governs entries, not the fields inside one.

   `tests/verify-config-consistency.sh` checks that this recovery text carries the closed-list re-resolution phrasing above and no longer grants the old status edit unconditionally.

   For each `waived` entry, confirm the category genuinely holds and a compensating control is named. For each `out-of-scope` entry, confirm the stated reason holds — "nothing assertable changed" is false the moment the fix altered behaviour.

   **If `<issue-folder>` is under `planning/reviews-orphan/`, `PASS` proves less than it looks.** That folder is one per long-lived branch, not one per incident, so several unticketed hotfixes share a ledger. A `PASS` there means *the entries present* are resolved — it cannot tell you this fix got an entry at all, because a missing entry is indistinguishable from a fix that needed none. Treat an orphan `PASS` the way Step 6b treats `N/A`: ask explicitly whether anything failed during this work, and confirm an entry exists naming *this* symptom before accepting it.

   **Step 6d — On failure, BLOCK:**

   ```
   ✗ BLOCKER: observed failure not covered by a test
       failure: <one-line description of what was observed>
       entry:   <ledger entry, or "no ledger entry exists">
       recovery: <keyed to the blocker kind — the gate names which one>
                 still open / no Status line  → add the regression test, or ask the user
                                                to approve a waiver and record it
                 N Status lines (malformed)   → keep exactly one; edit it in place
                 unrecognized Status value    → use open | covered | waived | out-of-scope
                 unclosed code fence          → indent pasted output four spaces instead
                 covered but no Test:         → re-resolve it through the closed list, or
                                                blank the field — the issue's next
                                                `/implement` then owes a live test
                 waived but no <field>        → the user supplies category and approval;
                                                you may not self-approve
                 ledger exists but no entries → ask Step 6b's question; if nothing failed,
                                                the ledger is spurious — delete it
                 out-of-scope but no Reason:  → name the clause from the closed list in
                                                `### Out of Scope` of the fragment
   ```

   Verification is **incomplete** while this blocker stands. Do not update planning state, do not report a full pass, and do not proceed to `/complete`. A waiver requires the user's explicit approval — never self-waive, and apply the approval test in the fragment's Waiver section rather than treating assent as approval.

7. **On-device verification:**

   **Step 7a — Ask the user. Every run, before anything else in this step:**

   ```
   Run on-device tests for this work? (yes / no)
   ```

   Ask it as its own message and wait for the answer. **Do not infer it** — not from `analysis.md` `## On-Device Scope`, not from the design doc, not from the file tree, not from the task description. Inference is what this step used to do, and it failed silently in both directions: a scope field nothing had written meant the step never ran, and a folder holding a full bench-run record sat beside a scope field reading `NO`. A question the user sees is the only form of this gate whose absence is visible.

   This is a question, not a proposal — the user's answer decides, and neither answer needs justifying. It is a workflow-mandated prompt, not a phase transition, so the assent test in `~/.claude/CLAUDE.md` → Critical Rules does not govern it: that rule bars treating assent as authorization to *advance a phase*, and this question advances none.

   **Record the answer where a later reader can find it**, the way Step 6b records its negative result: one line in the `/verify` output **and** appended to the `progress.md` Active entry — `on-device: run` or `on-device: declined by user`. Write that line even when the run does not fully pass; `## Planning State Update` below is gated on a full pass, so this step cannot delegate the record to it. An answer that lives only in conversation is unauditable one turn later, which makes skipping the question free — the same silent-skip this step was rewritten to remove.

   **If no answer can be obtained in this run** — no interactive user, a scheduled or non-interactive invocation, or a reply that is neither yes nor no — do not assume either branch. Record `on-device: not asked (no interactive user)` and treat the on-device requirement alone as incomplete, exactly as Step 7e does. Assuming `no` restores the silent skip; assuming `yes` walks into 7c's second question with nobody to answer it.

   **Step 7b — On `no`:** record that line and this step is done. Nothing else in it runs, planning state is not withheld, and the question is not re-raised.

   **Step 7c — On `yes`, locate the entry point:**
   Check the active issue's design doc — `<issue-folder>/design.md`, reusing the `<issue-folder>` Step 6a resolved rather than re-deriving it — for an `**Entry point:**` line. If the On-Device Verification section is absent, or present with no `**Entry point:**` line, ask the user for the command to run rather than erroring out: the user has already said the device matters for this work, so a missing design field is a documentation gap, not a reason to refuse. Record which one you used. Do not guess an entry point from project files.

   **Step 7d — Run it:**
   ```bash
   <entry-point>   # e.g. make verify-device, scripts/verify-device.sh, ./dev.sh test-device
   ```
   **Read the output on every exit status, then classify.** Exit `0` is a pass **only if the output shows a device was actually reached** — a script that prints `no device attached` and exits `0` is an ordinary shape, and treating its status alone as the verdict reports a passing device run on a machine with no device. Route any no-device report to Step 7e whatever the exit code, and a real device failure to Failure Handling item 6. A pass ends this step.

   **Step 7e — Device unreachable:**
   When the entry point reports no device, flag explicitly: "On-device verification pending — run `<entry-point>` on a device or record passing CI/HIL device evidence before merge." Treat verification as incomplete — do not update planning state and do not proceed to `/complete` until CI evidence of a passing device run is produced and recorded in the issue folder (e.g., a CI log link in a `device-verification.md` file). This is a blocker, not an advisory. It fires only after the user asked for the run, so it never blocks work the user already declined. Steps 8 and 9 have already run by this point, so their results still stand and are still reported.

8. **Attribution — which requirement does each changed file serve?**

   **Run this immediately after step 6, not in numbered order.** It needs two git commands and one document read, so it must not wait behind the test suite or a device run. The number is 8 only so steps 1–7 keep theirs.

   Resolve the base the way `commands/verify-docs.md` → Step 1 does — `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`, falling back to `git remote show origin`. Do not hardcode `origin/master`; step 2a above does, and it is wrong for a repo whose default is `main`. Then list the changed files:

   ```bash
   BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
     || BASE=$(git remote show origin | sed -n 's/.*HEAD branch: /origin\//p')
   : "${BASE:=$(git rev-parse --verify --quiet origin/main >/dev/null && echo origin/main)}"
   : "${BASE:=$(git rev-parse --verify --quiet origin/master >/dev/null && echo origin/master)}"

   git diff --name-only "${BASE:?}"...HEAD    # three-dot: this branch's own commits
   git diff --name-only                       # uncommitted work
   git ls-files --others --exclude-standard    # a new file is invisible to every git diff form until `git add`
   ```

   **Three-dot, not two.** `git diff --name-only "$BASE"` compares the working tree against the base tip, so it lists files a teammate changed upstream that this branch never touched — and the rule below would then report them as discovered work and halt a clean run. Three-dot diffs against the merge base instead, which is the branch's own contribution.

   **If the base cannot be resolved at all** — `origin/HEAD` unset, the remote unreachable, and neither fallback present — `${BASE:?}` aborts the block and `git ls-files` never runs. Report `attribution: base unresolved` and run steps 8 and 9 against the second and third commands alone, marking the result as covering uncommitted work only. A dangling `origin/HEAD` (branch deleted upstream) exits `0` with an invalid value, so neither the `||` fallback nor `${BASE:?}` fires — if `git diff` then aborts, treat it as the unresolved case rather than as an empty diff.

   For each file, name the goal or requirement it serves. Take those from the design doc for this work if one exists — you have it in this session; do not go resolving a path for it — otherwise from the issue's Scope and Acceptance Criteria. **If there is neither, say so in one line and move on.** Unticketed hotfix and CI work is the common case, not an edge case, and firing against nothing would mark every file unattributed and teach the reader to ignore this.

   A file serving nothing is **discovered work, not a defect**. Report it with the branch's `+N LOC` from `git diff --stat`, and do not report a full pass — the `## Planning State Update` rule below already withholds planning state when a check fails. Do not create a ticket or propose one: `/ticket` is user-invoked, so the split is the user's call and this check terminates in telling them.

   One thing this does not reach: anything under `planning/` (gitignored, so no diff form counts it).

9. **Comment ratio — is the new code carrying more explanation than it should?**

   **Run this with step 8, against the same resolved base.** One script over the same diff.

   ```bash
   BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
     || BASE=$(git remote show origin | sed -n 's/.*HEAD branch: /origin\//p')
   bash ~/.claude/scripts/comment-gate.sh "${BASE:?could not resolve the default branch}"
   ```

   Exit `0` means the scan ran — read the output. A non-zero exit means it did not, so the check is unmet rather than passed; exit `127` means the script is not installed, and `./sync-configs.sh install --claude` run from your `genai-automations` checkout installs it. Per file the output carries `PASS`, `WARN`, `BLOCK`, `small` (under `MIN_ADDED_CODE`, so no ratio is reported), or `skip` (path not readable, comment syntax unknown for that extension, or no added lines resolved), plus each bare suppression marker, each `TODO`/`FIXME` with no ticket reference, each body-comment run longer than `MAX_COMMENT_RUN`, and each comment citing a planning document or a `§N` section.

   `WARN` and `small` are reported and do not stop the run. **`skip` splits in two:** an unknown comment syntax for that extension is reported and does not stop the run — Markdown command files skip on every run here — but `skip` because the **path was not readable** is a failure, because that file was never scanned and the Requirements bullet below claims every changed file was. Name the file and the reason. Under `## Failure Handling` below, `BLOCK` and any flag — a bare suppression, an unreferenced `TODO`, an over-long comment run, a planning reference — is a failure: the comment-gate item there carries the recovery, and the run restarts from step 1. The thresholds are guesses under tuning and the flags are stricter than the sanctioned cases in `skills/domains/code-quality/SKILL.md` — where a `BLOCK` or any flag is genuinely wrong, stop and say so rather than editing the constant or deleting the marker. A `BLOCK` driven by comments inside an embedded language or a heredoc — an awk program, a `sed` script, a heredoc carrying Markdown — is the known false positive and the expected case for saying so.

## Requirements

- ✅ The linter question was settled — linters discovered and available, or the user was asked and their choice recorded; `skipped by user` satisfies this, deciding it yourself does not
- ✅ Comment-rule coverage reported — which of `ruff`'s `D`/`ERA001`, `revive`'s `exported`, and `missing_docs` the repo leaves off (step 1d)
- ✅ Every changed file serves a named goal or requirement, or is reported as discovered work — satisfied by the documented one-line skip when there is no design doc and no issue
- ✅ Zero linter errors/warnings
- ✅ Code formatting applied
- ✅ C++ clangd analysis complete — no missing implementations, no suspicious short methods
- ✅ Zero test failures — or `not run`, where no suite was discovered. A repo with no tests does not satisfy this bullet vacuously; say which
- ✅ Zero static analysis errors — or `not run`, on the same rule
- ✅ No breaking changes (or properly documented)
- ✅ Every entry in `<issue-folder>/observed-failures.md` is resolved — covered by a test that asserts its actual symptom, waived with user approval, or justified as out-of-scope; and no observed failure is missing an entry
- ✅ Build passes
- ✅ The on-device question was asked and its answer recorded — `declined by user` satisfies this; inferring the answer does not. On `yes`: verification passed locally, or passing CI/HIL device evidence is recorded when no local device is available
- ✅ Comment ratio run over every changed file — no `BLOCK` and no flag (bare suppression, ticketless `TODO`/`FIXME`, over-long comment run, planning reference), or each is reported as a pre-authorized false positive — satisfied by the stop-for-the-user's-decision handoff in Failure Handling item 8

## Failure Handling

If any check fails:
1. **Linter failures:** Fix code style, type errors, or warnings immediately
2. **Clangd findings:** Fix missing implementations or logic bugs before running tests
3. **Test failures:** Debug and fix the failing tests
4. **Static analysis issues:** Address security or code quality concerns
5. **Missing regression coverage:** Write the test specified by the diagnosis, confirm it fails against the unfixed code, then record it in the ledger and re-run Step 6a. If the failure is genuinely untestable, ask the user to approve a waiver — do not proceed on your own judgement.
6. **On-device verification failures:** Check the failure indicators listed in the design doc's On-Device Verification section; fix the underlying issue (firmware, deploy step, or test logic) and re-run the entry-point script. If the device is unavailable, leave the explicit pending statement from Step 7e in place and do not mark as verified. A `no` at Step 7a is not a failure and reaches none of this.
7. **Unattributed changed file:** report it with the branch's `+N LOC` and stop for the user's decision — split it out, or widen the design's goals to cover it. Do not create a ticket, and do not resolve it by inlining an explanation of why the file is fine.
8. **Comment gate `BLOCK` or flag:** delete the body comments the code does not need, or rewrite the code those comments are compensating for; give a bare suppression marker its reason and an unreferenced `TODO` its ticket; split or cut a comment run past `MAX_COMMENT_RUN`, extracting a named function where the WHY needs the room; and replace a planning-document citation with what the reader of a clone can actually resolve. Where the verdict is genuinely wrong, report it and stop for the user's decision — do not edit the constants and do not delete the marker.
9. Re-run verification from step 1 (linters)
10. Do NOT proceed to completion until all checks pass

## Execution Order is Critical

**Always run in this order** — this list is the order of record, and it is not the numbering of the steps above:

1. Linters (step 1 — fix code quality)
2. Clangd analysis (step 2 — C++ only; catch missing impls and type bugs)
3. Tests (steps 3 and 4 — verify correctness)
4. Static analysis (step 5 — security/quality)
5. Regression check plus the observed-failure ledger gate (steps 6a–6d)
6. **Attribution and comment ratio (steps 8 and 9)** — two git commands and one document read; they must not wait behind a device run
7. **On-device (step 7)** — last, because Step 7a blocks on a human answer and Step 7d can take minutes

Do NOT run tests before linters and clangd pass. This ensures clean code before verification. Step 7 is numbered 7 only so the earlier steps keep their numbers; it runs last.

## Planning State Update (on full pass only)

When **all checks pass**, update planning state:

- In `planning/<goal>/milestone-XX/status.md`, append `| verified ✅` to the Notes column for the active issue.
- In `planning/progress.md` Active entry, append or replace: `- verification ✅ (linters + tests + itest)`.
- Update `**Last Updated:**` to today's date.

The `on-device:` line is **not** part of this update — Step 7a writes it on every run, pass or fail, because `/complete` reads it as a precondition and a line that only appears on a full pass cannot distinguish "declined" from "never asked".

Then push planning to backup:
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```
Follow the steps in that fragment. Surface the §8.2 warning block on failure; do not fail the skill.

**Do not update planning state if any check fails** — the failure is visible to the user; a stale "verified ✅" in planning would be worse than no entry.

## Next Step

**Next step:** Do not auto-propose a commit message or invoke `/complete`. Wait for the user to explicitly initiate a commit directive or type `/complete`. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization — see CLAUDE.md Critical Rules for the two-part test.
