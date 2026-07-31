---
name: complete-workflow
description: 8-phase software development workflow with mandatory design and code review checkpoints. Use when starting any implementation task to follow the research → design → review → implement → review → verify phases.
allowed-tools: Bash, Glob, Grep, Read, Write, Edit, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 2.0.0
  category: workflows
  tags: [workflow, development, phases, review]
---

# Complete Workflow Skill

Phase map for the 8-phase workflow. **Each command file is the authoritative procedure for its phase** — this file routes, it does not restate. Duplicating a procedure here is how the copies drift: an earlier version of this file ordered a blind `projctl sync pull` for months after `/start` replaced it with the drift-check flow.

## Phases

| # | Phase | Command | Agent | Output |
|---|---|---|---|---|
| 0 | Start Work | `/start` | — | context loaded, drift checked, stale tickets flagged |
| 1 | Research | `/research` | architecture-research-planner | `issues/<NNN-name>/analysis.md` |
| 2 | Design | `/design` | Q&A in main conversation, then architecture-research-planner | `issues/<NNN-name>/design.md` |
| 3 | Design Review | `/review-design` | 3 × reviewer + Codex | `issues/<NNN-name>/design-review.md` |
| 4 | Implementation | `/implement` | coder **or** devops-engineer | code + tests |
| 5 | Code Review | `/review-code` | 3 × reviewer + test-coverage + Codex | `issues/<NNN-name>/code-review.md` |
| 6 | Verification | `/verify` | — | linters → tests → static analysis → ledger gate |
| 7 | Commit | — | — | user commits; single-line message |
| 8 | Completion | `/complete` | — | `progress.md` updated, planning pushed |

Read the command file for the phase you are entering. Nothing in this file substitutes for it.

## Gates

Three gates block the workflow. Each is defined in full elsewhere; none is summarised here in a form that could disagree with its source.

| Gate | Fires at | Source |
|---|---|---|
| Phase gate — the AI never auto-advances between phases | every transition 0→1 … 7→8, and inter-issue after 8 | `~/.claude/CLAUDE.md` → Critical Rules |
| Review checkpoints — design review before code, code review after | Phases 3 and 5 | `~/.claude/CLAUDE.md` → Critical Rules |
| Observed-failure regression — every failure that happened gets a test | Phases 4, 5, 6 | `~/.claude/skills/workflows/regression-test/SKILL.md` |

Reviewer `APPROVED` is a precondition for asking the user, never a substitute for the user's answer. Conversational acknowledgements are not authorization — the two-part test is in CLAUDE.md → Critical Rules.

## Standing Rules

- **Never create git commits** — the user handles every commit.
- **Never update `progress.md` automatically** — propose, then wait for confirmation.
- **Never pass `isolation: "worktree"` to coder or devops-engineer** — changes would land in a throw-away branch and need manual recovery. Omit the parameter.
