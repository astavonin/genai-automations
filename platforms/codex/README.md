# Codex Configuration Backup

Backup of the tracked Codex configuration for architecture/design work plus implementation support in **C++**, **Python**, and **Go**.

## Scope

This tracked backup currently includes:
- design docs and architecture research
- architecture review
- language guidance for C++, Python, and Go
- shared coding guidance for testing and code quality

It does not attempt to restore the full Claude-side surface area.

## Structure

```text
platforms/codex/
├── CODEX.md
├── README.md
└── skills/
    ├── architecture-research-planner/
    ├── reviewer/
    ├── domains/
    │   ├── architecture/
    │   ├── code-quality/
    │   ├── quality-attributes/
    │   └── testing/
    ├── languages/
    │   ├── cpp/
    │   ├── go/
    │   └── python/
    └── workflows/
        └── architecture-review/
```

## References

- Main guide: `CODEX.md`
- Claude source material used for restoration lives under `../claude/skills/` and `../claude/agents/coder.md`
