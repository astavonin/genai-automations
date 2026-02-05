# Codex Configuration Backup

Backup of `~/.codex/` focused on **code reviews**, **issue investigations**, and **architecture reviews**.

## Structure

```
platforms/codex/
├── CODEX.md                    # Main workflow guide
├── README.md                   # This file
│
├── skills/                     # Primary behavior and workflows
│   ├── workflows/
│   │   ├── code-review/        # Review workflow + output template
│   │   ├── issue-investigation/# Investigation workflow + output template
│   │   └── architecture-review/# Architecture review workflow + output template
│   ├── domains/                # Quality attributes, code quality, testing, architecture
│   ├── languages/              # Language standards
│   ├── reviewer/               # Review persona
│   └── architecture-research-planner/ # Investigation persona
│
└── agents/                     # Reference only (not used by Codex UI)
```

## Focus (2026-02-05)

Codex is deliberately scoped to three workflows:
- **Code Review** — high-signal, checklist-driven reviews
- **Issue Investigation** — evidence-based analysis and recommendations
- **Architecture Review** — design quality, trade-offs, and evolution

## Usage

Codex uses skills for workflows. Use:
- `skills/workflows/code-review/`
- `skills/workflows/issue-investigation/`
- `skills/workflows/architecture-review/`

### Syncing to `~/.codex/`

```bash
# Backup current setup (if any)
cp -r ~/.codex ~/.codex.backup-$(date +%Y%m%d)

# Sync from backup repo (careful - overwrites)
rsync -av --exclude='.git' platforms/codex/ ~/.codex/
```

### Syncing from `~/.codex/`

```bash
rsync -av --exclude='.git' ~/.codex/ platforms/codex/
```

## References

- Main guide: `CODEX.md`
- Review checklist: `skills/domains/quality-attributes/references/review-checklist.md`
- Review template: `skills/workflows/code-review/references/review-output-template.md`
- Investigation template: `skills/workflows/issue-investigation/references/investigation-template.md`
- Architecture review template: `skills/workflows/architecture-review/references/architecture-review-template.md`
