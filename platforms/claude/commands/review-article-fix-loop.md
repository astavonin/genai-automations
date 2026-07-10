---
name: review-article-fix-loop
description: Run initial article review, fix all High and Medium findings, re-review until APPROVED, then run one final clean review and print the report
---

# Article Review Fix Loop Command

Run the full article review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer (opus)** — all review passes (full `/review-article` multi-agent protocol each time)
- **writer (opus)** — all article edits; fixes must stay within the article draft (`draft.md`); the writer may read the companion repo and spec for context but must not modify them

## Prerequisite

Both `spec.md` and `draft.md` must exist in the active issue folder before Step 1. No existing `article-review.md` required — this command produces it. If either file is missing, stop and report which is absent.

## Protocol Deviations

When running any review pass in this command (Steps 1, 3, 4), deviate from the `/review-article` protocol as follows — these steps are suppressed because the fix-loop manages them centrally:

- **Skip** the planning-update step (Step 5 of this command handles it once at the end)
- **Skip** the push-planning step (Step 5 handles it)
- **Skip** the "ask user to open file" step (this command runs autonomously)
- **Skip** the "Block until the user explicitly approves" step (the loop continues without user input — authorized by the Exception clause in CLAUDE.md Critical Rules)
- **Step 4 only — additionally skip:** the prior-review pre-read step. Do not read or pass the existing `article-review.md` to any agent in Step 4. Treat this pass as if no prior review file exists.

## Actions

**Preamble:** Initialize `iteration = 0` before Step 1. Set exactly once at command start; never reset mid-run.

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial article review..."

Follow `/review-article` with the deviations listed above. Writes `article-review.md`.

If result is `APPROVED`: proceed directly to Step 5. Step 1's output is already a clean report — skip Steps 2–4.

If result is `CHANGES REQUESTED`: proceed to Step 2.

### Step 2: Fix all findings

Declare: "I'll use writer agent to fix all findings from the current review..."

**Which findings to fix:** Fix all High and Medium findings. For Low: fix those with a concrete fix direction stated in the review; skip advisory-only entries. Apply this rule without asking the user.

Invoke **writer (opus)** with:
- The full `draft.md` content
- The full `spec.md` content (for accuracy and completeness context)
- Companion repo source files that were pre-read during the review (pass inline; the writer must not call Read itself)
- The full list of findings selected above
- Instruction: apply all fixes to `draft.md` in one pass; preserve all `<!-- file: path:L10-L25 -->` annotations and `<!-- TODO[ID] -->` markers — do not remove or reformat them; fix prose, code accuracy, completeness, and consistency issues as stated in each finding; do not add new `<!-- TODO[ID] -->` markers unless a finding explicitly requires it; flag explicitly any finding that cannot be addressed; do not make changes beyond the scope of the listed findings

**If the writer flags any finding as unaddressable:** surface it to the user immediately and wait for a decision before proceeding to Step 3 — do not silently continue.

**Annotation coherence check** — after the writer completes, verify that every fenced code block in `draft.md` still has an immediately-preceding `<!-- file: path:L10-L25 -->` annotation:

```bash
python3 -c "
import re, sys
text = open('path/to/draft.md').read()
blocks = list(re.finditer(r'(<!--[^>]*-->)?\n*\`\`\`', text))
# simplified: grep for code fences without annotations
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith('\`\`\`') and len(line) > 3:
        prev = lines[i-1].strip() if i > 0 else ''
        if not prev.startswith('<!--'):
            print(f'Line {i+1}: code block missing annotation')
"
```

Or use: `grep -n '^\`\`\`' draft.md | head -20` to list all opening fences and verify each has an annotation in the preceding line. If any annotation is missing, invoke writer again scoped to re-adding the missing annotations only before proceeding to Step 3.

### Step 3: Re-review

Increment `iteration` (`iteration += 1`). Declare: "I'll use reviewer agent for re-review pass [N]..." where N is the current value of `iteration`.

Follow `/review-article` with the deviations listed above. **Pass the current `article-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `article-review.md`.

If result is `APPROVED`: proceed to Step 4.

If result is `CHANGES REQUESTED`: return to Step 2.

**Stall detection:** If the same root-cause area (same article section + same scope criterion — not finding ID, which resets each pass) appears unresolved in 3 consecutive passes, run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`)

This is a terminal stop. Surface the stall and output:
```
Article review loop paused — stall detected
Finding area [section/scope] unresolved after 3 passes.
Iterations completed: [iteration]
Re-invoke /review-article-fix-loop after addressing the stalled finding manually.
```

### Step 4: Final clean review

Declare: "I'll use reviewer agent for the final clean review..."

Follow `/review-article` with **all** deviations listed above, including the Step 4 addition (skip prior-review pre-read). Overwrites `article-review.md`.

If this final clean review returns `APPROVED`: proceed to Step 5.

If this final clean review returns `CHANGES REQUESTED`: run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`)

Report to the user and stop:
```
Final clean review: CHANGES REQUESTED — N finding(s).
The fix loop converged but the clean pass found new issues. Review the findings and invoke /review-article-fix-loop again to address them.
```

### Step 5: Report and stop

Verify the status marker:
```bash
head -20 planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md | grep -m 1 '^\*\*Status:\*\*'
```

**Cross-article TODO update:** If `planning/book/todos.md` exists, check whether any open entries were resolved during this review cycle:
- Type A entries (Referenced in this article) whose `<!-- TODO[ID] -->` marker was removed from the draft
- Type B entries (Resolves in this article) whose content is now covered

Propose the exact row moves from `## Open` to `## Resolved` (with today's date). Wait for explicit user confirmation before writing.

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`, `approved_next = ready for publication or revision`, `escalation = standard`)

Output:
```
Article review loop complete: APPROVED
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
Final report: planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md
```

Stop. Do not proceed to publication automatically.
