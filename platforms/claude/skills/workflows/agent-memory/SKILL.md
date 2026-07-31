---
name: agent-memory
description: Shared fragment — how every agent uses its persistent memory directory. Read by the reviewer, coder, devops-engineer, architecture-research-planner, debugger, and writer agents. Holds the rules common to all of them; each agent file carries only its own directory path and its own what-to-save list.
allowed-tools: Glob, Grep, Read, Write, Edit
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [agents, memory, persistence]
---

# Persistent Agent Memory — Shared Fragment

**This file is the single source for these rules.** Agent files name their own directory and their own what-to-save list, then point here. Do not restate the rules below in an agent file.

Your memory directory is `~/.claude/agent-memory/<your-agent-name>/`. Its contents persist across conversations.

## Reading

**Read `MEMORY.md` in your directory before starting work.** It is the index. Do not assume it is empty — an agent that skips the read re-derives what a previous run already established. An absent file means nothing has been saved yet, not that memory is unavailable.

Consult the topic files it links as the task warrants. When you hit a mistake that looks like it could recur, check memory for a relevant note first; if nothing is written, record what you learned.

Keep detailed notes in topic files linked from `MEMORY.md` — see Writing below for the file shape.

## Writing

- `MEMORY.md` is loaded into your system prompt — lines after 200 are truncated, so keep it an index, not a store
- Put detailed notes in topic files and link them from `MEMORY.md`
- Organize semantically by topic, never chronologically
- Update or delete memories that turn out to be wrong or outdated
- Use Write and Edit to maintain the files

## What NOT to Save

- Session-specific context — current task details, in-progress work, temporary state
- Anything you have not verified against project docs
- Anything that duplicates or contradicts `~/.claude/CLAUDE.md`
- Speculative conclusions drawn from a single file or a single artifact

## Explicit User Requests

- Asked to remember something across sessions: save it immediately
- Asked to forget something: find and remove the entries
- Corrected on something you stated from memory: fix or delete that entry before continuing
