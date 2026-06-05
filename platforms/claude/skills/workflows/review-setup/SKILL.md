---
name: review-setup
description: Shared fragment — reads the quality-attributes skills needed before running any review (design, code, fix, MR). Always the first step of every review command.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, setup, skills]
---

# Review Setup — Shared Fragment

Read the quality-attributes skills before starting any review. This is the first step of every review command (`/review-design`, `/review-code`, `/review-fix`, `/review-mr`).

## Steps

```
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
Read ~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md
```

All three must be read before launching any reviewer agent. The review checklist and consensus protocol are passed inline to every agent prompt.
