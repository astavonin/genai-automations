---
name: review-article-fix-loop
description: Run initial article review, fix all High and Medium findings, re-review until APPROVED or the iteration cap, then print the report
---

# Article Review Fix Loop Command

Run the full article review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED or the iteration cap → report.

## Usage

```
/review-article-fix-loop                       # infers all paths from current issue context
/review-article-fix-loop <issue-folder-path>    # explicit issue folder — REQUIRED for an appendix page, since progress.md can never resolve one
```

## Agents

- **reviewer (opus)** — all review passes (full `/review-article` multi-agent protocol each time)
- **writer (opus)** — all article edits; fixes must stay within the article draft (`draft.md`); the writer may read the companion repo and spec for context but must not modify them

## Prerequisite

Both `spec.md` and `draft.md` must exist in the issue folder — the argument if one was given, else derived from the active issue in `planning/progress.md` (main articles only; an appendix page must be given explicitly, per `~/.claude/skills/workflows/page-type/SKILL.md` → "Obtaining the path"). `<issue-folder>` below means this resolved path. No existing `article-review.md` required — this command produces it. If either file is missing, stop and report which is absent.

Every `/review-article` pass below (Steps 1 and 3) receives the same issue-folder-path argument this command was invoked with, if any.

## Protocol Deviations

When running any review pass in this command (Steps 1 and 3), deviate from the `/review-article` protocol as follows — these steps are suppressed because the fix-loop manages them centrally:

- **Skip** the planning-update step (Step 5 of this command handles it once at the end)
- **Skip** the push-planning step (Step 5 handles it)
- **Skip** the "ask user to open file" step (this command runs autonomously)
- **Skip** the "Block until the user explicitly approves" step (the loop continues without user input — authorized by the Exception clause in CLAUDE.md Critical Rules)
- **Skip** the "After Final Approval: Update todos.md" step — Step 5 of this command handles todos.md updates once at the end

## Actions

**Preamble:** Initialize `iteration = 0` before Step 1. Set exactly once at command start; never reset mid-run.

**Review-planning-update parameters** — all `review-planning-update` invocations in this command use identical parameters (shown inline at each call site for readability; listed here once as the single source of truth):
`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`, `issue_folder = <issue-folder>`

### Step 1: Initial review

Follow `/review-article` with the deviations listed above. Writes `article-review.md`.

If result is `APPROVED`: proceed directly to Step 5. Step 1's output is already a clean report — skip Steps 2 and 3.

If result is `CHANGES REQUESTED`: proceed to Step 2.

### Step 2: Fix all findings

**Which findings to fix:** Fix all High and Medium findings. For Low: fix those with a concrete fix direction stated in the review; skip advisory-only entries. Apply this rule without asking the user.

**Before invoking the writer** — substitute the actual `draft.md` path and capture current `<!-- TODO[ID] -->` ID counts to a file. A fixed path is used because each bash call runs in a fresh shell; shell variables do not persist between calls but filesystem paths do:

```bash
grep -oE 'TODO\[[^]]+\]' /path/to/draft.md | sort | uniq -c > /tmp/article-review-todos-before.txt
```

Invoke **writer (opus)** with:
- The full `draft.md` content
- The full `spec.md` content (for accuracy and completeness context)
- Companion repo source files that were pre-read during the review (pass inline; the writer must not call Read itself)
- The full list of findings selected above
- Instruction: apply all fixes to `draft.md` in one pass; preserve all source annotations in either form — GitHub permalinks and legacy `<!-- file: path:L10-L25 -->` comments — and all `<!-- TODO[ID] -->` markers — do not remove or reformat them; fix prose, code accuracy, completeness, and consistency issues as stated in each finding; do not add new `<!-- TODO[ID] -->` markers unless a finding explicitly requires it; flag explicitly any finding that cannot be addressed; do not make changes beyond the scope of the listed findings

**If the writer flags any finding as unaddressable:** delete the snapshot, run the review-planning-update fragment (which includes push):
```bash
rm -f /tmp/article-review-todos-before.txt
```
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`, `issue_folder = <issue-folder>`)

Then surface the finding to the user and stop:
```
Article review loop paused — unaddressable finding
Iterations completed: [iteration]
[Finding description]
Re-invoke /review-article-fix-loop after resolving the finding manually.
```

**After the writer completes — combined verification (shared 3-attempt budget):**

Both checks share a single budget of 3 writer re-invocations. The snapshot is kept until both checks pass or the budget is exhausted. Each round is exactly one writer invocation: collect all failures from both checks, combine their diagnostic outputs into a single prompt, invoke the writer once, then re-run both checks. One round = one budget tick regardless of how many checks failed in that round.

**1. TODO marker preservation check** — substitute the actual `draft.md` path:

```bash
diff /tmp/article-review-todos-before.txt <(grep -oE 'TODO\[[^]]+\]' /path/to/draft.md | sort | uniq -c)
```

Compare the dropped IDs against the finding list; for any ID drop that was NOT explicitly requested by a finding, add to the combined writer prompt: "The following TODO markers were dropped — restore them: [paste diff output]".

**2. Annotation coherence check.**

**Appendix pages: skip this check entirely** and treat it as passed. An A-page never cites code (`page-type/SKILL.md` → Resolution) — its fenced blocks are captured command output or evidence, not GitHub-permalinked source snippets — running this check against one asks the writer to fabricate a commit hash for evidence, the exact failure class this contract exists to prevent.

For a `main` page: substitute the actual `draft.md` path. The `prev_nonblank` pattern tolerates zero or more blank lines between annotation and fence. Limitations: indented fences, nested fenced blocks, and fences inside HTML comments are not detected.

```bash
awk '
  /^```/{
    if (in_block) { in_block=0; prev_nonblank="" }
    else { if (prev_nonblank !~ /<!--.*file:/ && prev_nonblank !~ /\/blob\/[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]+\//) print NR": code block missing annotation"; in_block=1 }
    next
  }
  /^[[:space:]]*$/ { next }
  { prev_nonblank=$0 }
' /path/to/draft.md
```

The predicate accepts either annotation form — the `<!-- file: ... -->` HTML comment, and the GitHub permalink of `SCOPES.md` → Scope 1.1 form (a), detected by `/blob/<hash>/` with at least seven hex characters, so a branch permalink such as `/blob/dev/` is not mistaken for a pinned one. Seven explicit character classes rather than `{7,}` because mawk ignores interval quantifiers. Recognising only the comment form would report every block of a correctly permalinked article as unannotated, and then ask the writer to add the unpinned form on top.

If any line is printed, add to the combined writer prompt: "The following code blocks are missing their source annotation — add a GitHub permalink (`SCOPES.md` Scope 1.1 form (a), using the article-wide commit hash) on the line immediately before each fence: [paste awk output]".

After each writer re-invocation, re-run both checks. If either check still fails and the shared budget is exhausted, surface a blocker including the last diagnostic output:

```
Post-writer verification failed after 3 attempts — manual intervention needed.
Last diagnostic: [paste last diff/awk output]
```

After both checks pass (or after surfacing a blocker), delete the snapshot:

```bash
rm -f /tmp/article-review-todos-before.txt
```

### Step 3: Re-review

```
Read ~/.claude/skills/workflows/fix-loop-round/SKILL.md
```

Follow `/review-article` with the deviations listed above. **Pass the current `article-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `article-review.md`.

**This file is parsed by two tests.** `tests/verify-workflow-safety.sh` asserts this Step 3 carries the fragment's `Read` pointer above, ahead of a review-pass launch sentence that begins with the word `Follow`, with no destination sentence or increment of its own, that neither this file's frontmatter nor its body still promises the deleted review pass that used to follow Step 3, that every `Step <N>` reference in this file resolves to a heading here, and that the `### Cap-pause` and `### Stall stop` headings below exist and run their procedures in the order the fragment names. `tests/verify-config-consistency.sh` asserts the `Read` pointer above resolves to a non-empty file, and that the `### Cap-pause` message below names its report under `<issue-folder>/article-review.md` rather than a hardcoded milestone-form path — any `milestone-XX` segment, not one fixed literal. Editing the step numbering, the headings, the pointer, the report path, or the launch sentence's opening word without re-running both is how this drifts silently.

### Stall stop

If the same root-cause area (same article section + same scope criterion — not finding ID, which resets each pass) appears unresolved in 3 consecutive passes, delete the snapshot, then run the review-planning-update fragment (which includes push):
```bash
rm -f /tmp/article-review-todos-before.txt
```
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`, `issue_folder = <issue-folder>`)

This is a terminal stop. Surface the stall and output:
```
Article review loop paused — stall detected
Finding area [section/scope] unresolved after 3 passes.
Iterations completed: [iteration]
Re-invoke /review-article-fix-loop after addressing the stalled finding manually.
```

### Cap-pause

```bash
rm -f /tmp/article-review-todos-before.txt
```

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`, `issue_folder = <issue-folder>`)

Report to the user and stop:
```
Article review loop paused — iteration cap reached
Iterations completed: [iteration]
N finding(s) open in <issue-folder>/article-review.md.
Fix them manually, or re-invoke /review-article-fix-loop to continue.
```

### Step 5: Report and stop

Verify the status marker:
```bash
head -20 <issue-folder>/article-review.md | grep -m 1 '^\*\*Status:\*\*'
```

**Cross-article TODO update:** If `planning/book/todos.md` exists and the TODO scan ran (check the `**TODO scan:**` field in `article-review.md` — skip this step if the field is missing OR reads `✗ skipped`), check whether any open entries were resolved during this review cycle:
- Type A entries (Referenced in this article) whose `<!-- TODO[ID] -->` marker was removed from the draft
- Type B entries (Resolves in this article) whose content is now covered

Propose the exact row moves from `## Open` to `## Resolved` (with today's date). Wait for explicit user confirmation before writing.

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`, `issue_folder = <issue-folder>`)

Output:
```
Article review loop complete: APPROVED
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
Final report: <issue-folder>/article-review.md
```

Stop. Do not proceed to publication automatically.
