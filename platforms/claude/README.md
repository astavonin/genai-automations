# Claude Code Configuration Backup

Backup of `~/.claude/` directory containing Claude Code configurations and workflows.

## Structure

```
platforms/claude/
├── CLAUDE.md                    # Simplified reference guide
├── README.md                    # This file
│
├── commands/                    # Executable workflow commands (8 files)
│   ├── start.md                # Load work context
│   ├── research.md             # Run research phase
│   ├── design.md               # Create design proposal
│   ├── review-design.md        # Design review checkpoint
│   ├── implement.md            # Run implementation
│   ├── review-code.md          # Code review checkpoint
│   ├── verify.md               # Run verification
│   └── complete.md             # Mark work complete
│
├── skills/                      # Knowledge base
│   ├── languages/               # Language-specific guidelines (6 languages)
│   │   ├── cpp/                # C++ Core Guidelines
│   │   ├── python/             # PEP 8, Google Style Guide
│   │   ├── go/                 # Effective Go
│   │   ├── rust/               # Rust API Guidelines
│   │   ├── zig/                # Zig Style Guide
│   │   └── shell/              # Shell scripting best practices
│   │
│   ├── domains/                 # Domain knowledge (4 domains)
│   │   ├── code-quality/       # Code quality principles
│   │   ├── quality-attributes/ # 8 quality attributes + review checklists
│   │   ├── architecture/       # Architecture patterns
│   │   └── testing/            # Testing strategies
│   │
│   └── workflows/               # Workflow knowledge (2 workflows)
│       ├── complete-workflow/  # 8-phase workflow reference
│       └── planning/           # Planning structure + templates
│
└── agents/                      # Agent definitions
    ├── architecture-research-planner.md
    ├── coder.md
    ├── devops-engineer.md
    └── reviewer.md
```

## Restructuring (2026-02-01)

The Claude setup was restructured from a monolithic `CLAUDE.md` into a modular, command-based architecture:

- **Commands:** Workflow phases are now executable via `/start`, `/research`, `/design`, etc.
- **Skills:** Knowledge extracted into reusable modules organized by language, domain, and workflow
- **CLAUDE.md:** Simplified to a quick reference guide

Key file locations:
- Planning templates: `skills/workflows/planning/references/templates.md`
- Review checklists: `skills/domains/quality-attributes/references/review-checklist.md`

## Usage

### Syncing to ~/.claude/

To restore this configuration to `~/.claude/`:

```bash
# Backup current setup (if any)
cp -r ~/.claude ~/.claude.backup-$(date +%Y%m%d)

# Sync from backup repo (careful - overwrites)
rsync -av --exclude='.git' platforms/claude/ ~/.claude/

# Or copy selectively:
cp platforms/claude/CLAUDE.md ~/.claude/
cp -r platforms/claude/commands ~/.claude/
cp -r platforms/claude/skills ~/.claude/
cp -r platforms/claude/agents ~/.claude/
```

### Syncing from ~/.claude/

To update this backup from your active `~/.claude/`:

```bash
# From genai-automations repo root
rsync -av --exclude='.git' ~/.claude/ platforms/claude/

# Or copy selectively:
cp ~/.claude/CLAUDE.md platforms/claude/
cp -r ~/.claude/commands platforms/claude/
cp -r ~/.claude/skills platforms/claude/
cp -r ~/.claude/agents platforms/claude/
```

## Available Commands

When synced to `~/.claude/`, these workflow commands become available:

- `/start` - Load current work context
- `/research` - Run research phase (architecture-research-planner agent)
- `/design` - Create design proposal
- `/review-design` - Review design before implementation (MANDATORY)
- `/implement` - Run implementation (coder or devops-engineer agent)
- `/review-code` - Review code after implementation (MANDATORY)
- `/verify` - Run verification (tests, linters, static analysis)
- `/complete` - Mark work complete and update progress

## Skills Organization

### Languages
- C++, Python, Go, Rust, Zig, Shell
- Each skill contains: standards, key principles, formatting, static analysis

### Domains
- **code-quality:** Comment philosophy, linter suppressions, formatting
- **quality-attributes:** 8 quality attributes, review checklists
- **architecture:** Patterns, Mermaid diagrams, trade-offs
- **testing:** TDD, test pyramid, mocking, coverage

### Workflows
- **complete-workflow:** 8-phase workflow reference
- **planning:** Planning structure, progress tracking, templates

## Agents

Four specialized agents:
- **architecture-research-planner** (opus): Research, architecture, documentation
- **coder** (sonnet): Implementation (C++, Go, Rust, Python)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure
- **reviewer** (opus): Quality reviews (design and code)

## References

- Main reference: `CLAUDE.md` (quick reference for all workflows)
- Detailed documentation: See individual skill files in `skills/`
- Planning templates: `skills/workflows/planning/references/templates.md`
- Review checklists: `skills/domains/quality-attributes/references/review-checklist.md`
