# Auto Memory

## User Preferences

### Workflow Integration
- Planning sync: Run `sync pull` at `/start`, `sync push` at `/complete`
- See `~/.claude/CLAUDE.md` and `~/.claude/skills/workflows/complete-workflow/SKILL.md`

## Project Context

### ci-platform-manager
- Multi-platform CI automation tool (GitLab/GitHub)
- Location: `/home/astavonin/projects/genai-automations/ci_platform_manager/`
- Config resolution: project-local → user-wide → defaults
- Legacy config support: auto-transforms old format, preserves `planning_sync`
