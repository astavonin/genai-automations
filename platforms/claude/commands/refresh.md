---
name: refresh
description: Reload behavioral configuration files and restore expected behavior in long sessions
---

# Refresh Command

Re-read all behavioral configuration files to restore expected behavior after session drift.

This is distinct from `/start` (which loads *project context*). `/refresh` reloads *behavioral settings*.

## Actions

1. Read core behavioral configuration:
   ```
   Read ~/.claude/CLAUDE.md
   ```

2. Read complete workflow definition:
   ```
   Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
   ```

3. Read agent definitions:
   ```
   Read ~/.claude/agents/reviewer.md
   Read ~/.claude/agents/coder.md (if exists)
   Read ~/.claude/agents/architecture-research-planner.md (if exists)
   ```

4. Read memory file for session startup instructions:
   ```
   Read ~/.claude/memory/spanish-translations.md
   ```

## Output

After reading all files, confirm to the user:

**Behavioral Configuration Refreshed**

Provide a concise confirmation summary covering:

- **Workflow mode**: 8-phase workflow with mandatory checkpoints (Phase 3: design review, Phase 5: code review)
- **Critical rules**:
  - NEVER create git commits automatically
  - NEVER update progress.md without explicit user confirmation
  - ALL implementations require design review BEFORE code
  - ALL code requires code review AFTER implementation
- **Agent assignments**:
  - `architecture-research-planner` (opus) → research, architecture, documentation
  - `coder` (sonnet) → implementation (C++, Go, Rust, Python)
  - `devops-engineer` (sonnet) → CI/CD, Docker, infrastructure
  - `reviewer` (opus) → design reviews and code reviews
- **Communication style**: No validation phrases, concise and direct, technical accuracy
- **Status**: Ready to operate under expected behavior
