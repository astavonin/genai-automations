# Codex Configuration Backup

Backup of the tracked Codex configuration for architecture/design work plus primary implementation execution for approved specifications in **C++**, **Python**, **Go**, **Rust**, and **Shell**.

## Scope

This tracked backup currently includes:
- design docs and architecture research
- architecture review
- language guidance for C++, Python, Go, Rust, and Shell
- shared coding guidance for testing and code quality
- specification-driven implementation execution
- code-review support through language, testing, and code-quality checklists

It does not attempt to restore the full Claude-side surface area.

The `skills/reviewer/` skill is intentionally scoped to architecture and design review. Code review uses the relevant language skill plus `skills/domains/testing/` and `skills/domains/code-quality/`; it should not route through the design-only reviewer skill.

## Structure

```text
platforms/codex/
├── CODEX.md
├── README.md
├── config.toml
├── rules/
├── templates/
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
    │   ├── python/
    │   ├── rust/
    │   └── shell/
    └── workflows/
        └── architecture-review/
```

## References

- Main guide: `CODEX.md`
- Claude source material used for restoration lives under `../claude/skills/` and `../claude/agents/coder.md`
