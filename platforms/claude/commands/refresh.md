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
   Read ~/.claude/agents/coder.md
   Read ~/.claude/agents/devops-engineer.md
   Read ~/.claude/agents/architecture-research-planner.md
   Read ~/.claude/agents/debugger.md
   Read ~/.claude/agents/writer.md
   ```

4. Read workflow and planning skills:
   ```
   Read ~/.claude/skills/workflows/planning/SKILL.md
   Read ~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md
   ```

5. Read domain skills:
   ```
   Read ~/.claude/skills/domains/architecture/SKILL.md
   Read ~/.claude/skills/domains/quality-attributes/SKILL.md
   Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
   Read ~/.claude/skills/workflows/regression-test/SKILL.md
   ```

6. Read command definitions for active workflow phases:
   ```
   Read ~/.claude/commands/design.md
   Read ~/.claude/commands/review-design.md
   Read ~/.claude/commands/review-code.md
   Read ~/.claude/commands/implement.md
   Read ~/.claude/commands/verify.md
   Read ~/.claude/commands/review-fix.md
   ```

## Output

After reading all files, confirm to the user in **one line**:

```
Behavioral configuration refreshed — <N> files reloaded.
```

Do not recite the rules back. The user wrote them; reprinting the workflow phases, critical rules, agent table, and communication style is the exact volume this config exists to suppress.

Add a second line **only** when a reload actually changed something you were doing — a rule you had drifted from, or a file that failed to load:

```
Corrected: <what you were doing> → <what the config requires>.
```
