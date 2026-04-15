# Mandatory Behavioral Rules (ALWAYS enforce)

## Agent Declaration — REQUIRED before every agent use

Before invoking ANY agent, always state:
```
"I'll use <agent-name> agent to <task-description>..."
```
This applies to: architecture-research-planner, coder, devops-engineer, reviewer, debugger, writer.
**Never silently launch an agent. Always declare it first.**

## Workflow Checkpoints — NEVER skip

- Design review (`/review-design`) MUST happen before any implementation
- Code review (`/review-code`) MUST happen after every implementation
- NEVER create git commits — user handles all commits
- NEVER **write** to `progress.md` without explicit user confirmation — but **always propose** the exact edits and wait for approval (proposing is required, not optional)

---

# Session Startup Protocol

## Critical: Load Referenced Files Immediately

When CLAUDE.md contains `Reference: <path>`, this is a **directive**, not a suggestion.

**MUST DO at session start:**
1. Scan CLAUDE.md for all `Reference:` lines
2. Immediately read each referenced file
3. Apply those instructions from the first user interaction

**Example:**
```markdown
Reference: `~/.claude/skills/languages/`
```
→ Read that file IMMEDIATELY and apply the coding guidelines from the start

**Why this matters:** User configured persistent behavior across sessions. Not loading references = ignoring user's standing instructions.

---

# Shell Scripting Preferences

- `feedback_shell_pipe_stderr.md` — Use `|&` instead of `2>&1 |` to avoid permission prompts

---

# Project Context

## ci-platform-manager
- Multi-platform CI automation tool (GitLab/GitHub)
- Location: `~/projects/ci-platform-manager`
- Config resolution: project-local → user-wide → defaults

## planning-mcp language and stack
- See `project_planning_mcp.md` — Go, not Python; may influence ci-manager migration later
