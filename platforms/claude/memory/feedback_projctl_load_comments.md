---
name: projctl-load-comments-flag
description: projctl load mr requires --comments flag to include MR comments; check --help before falling back to gh/glab
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 91c852b3-c48e-4362-9c41-17284cd43801
---

Use `projctl load mr <N> --comments` when the user asks about MR comments, review notes, or discussion. Without `--comments`, the output contains only MR metadata — no comments.

**Why:** Attempted `projctl load mr 198` (no flag), got no comments, then fell back to `gh api` — which violates the projctl-only rule and fails on GitLab repos. The flag exists but was undiscovered.

**How to apply:** Before concluding projctl can't do something, run `projctl <subcommand> --help`. The `--comments` flag appears at the top level: `projctl load [-h] [--comments] {issue,epic,milestone,mr}`. Never reach for `gh api` or `glab` until help output confirms the feature is absent.
