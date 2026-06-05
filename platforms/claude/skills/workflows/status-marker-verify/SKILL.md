---
name: status-marker-verify
description: Shared fragment — verify the **Status:** marker in a review file after writing it. Used by review-design and review-code before updating planning state.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, marker, verification]
---

# Status Marker Verify — Shared Fragment

Verify the canonical status marker in a review file. Call this immediately after writing any review file and before updating planning state.

## Convention (§4)

Every review file MUST contain exactly one status marker as the **first non-empty line after the H1 title**, within the first 20 lines:

```
**Status:** APPROVED
```

Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED` — all uppercase, no emoji, no verb/noun mixing.

This marker is machine-readable and used by the `/implement` gate. A review without the canonical marker causes the compaction gate to skip.

## Caller Must Specify

- **`review_file`** — path to the review file just written (e.g., `planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md`)

## Verification Step

```bash
head -20 <review_file> | grep -m 1 '^\*\*Status:\*\*'
```

- If the marker is found with a canonical state (`APPROVED`, `CHANGES REQUESTED`, or `REJECTED`) → proceed.
- If the marker is **missing or malformed** → **do not declare the review complete**. Surface this error:
  ```
  ⚠️  review incomplete: status marker missing or malformed in <review_file>
      reason: head -20 found no line matching ^\*\*Status:\*\*
      recovery: re-invoke the reviewer agent with an explicit instruction to include the marker,
                or add the marker manually before continuing
  ```
  Do not proceed to planning state update until resolved.
