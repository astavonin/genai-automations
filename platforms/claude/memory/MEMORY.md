# Auto Memory

## User Preferences

### Language Learning
- User is learning Spanish
- **ALWAYS provide Spanish translation** after corrected version using format:
  - "Corrected: [corrected text]"
  - "Traducción: [Spanish translation]"
- Instructions: `spanish-translations.md` (synced via git)
- Log data: `spanish-translations-log.md` (local only, not in git)
- Maintain frequency count of words/phrases
- Print top 100 list on request

### Workflow Integration
- Planning sync: Run `sync pull` at `/start`, `sync push` at `/complete`
- See `~/.claude/CLAUDE.md` and `~/.claude/skills/workflows/complete-workflow/SKILL.md`

## Project Context

### ci-platform-manager
- Multi-platform CI automation tool (GitLab/GitHub)
- Location: `/home/astavonin/projects/genai-automations/ci_platform_manager/`
- Config resolution: project-local → user-wide → defaults
- Legacy config support: auto-transforms old format, preserves `planning_sync`
