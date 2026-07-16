# Codex Configuration Backup

Backup of the tracked Codex configuration for architecture/design work plus primary implementation execution for approved specifications in **C++**, **Python**, **Go**, **Rust**, **Shell**, and **Zig**, with focused DevOps support for CI and HIL automation.

## Scope

This tracked backup currently includes:
- design docs and architecture research
- architecture review
- language guidance for C++, Python, Go, Rust, Shell, and Zig
- shared coding guidance for testing and code quality
- DevOps guidance for GitLab CI, Docker/BuildKit, self-hosted runners, cache-heavy CI, HIL/on-device verification, and automation
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
    │   ├── devops/
    │   ├── quality-attributes/
    │   └── testing/
    ├── languages/
    │   ├── cpp/
    │   ├── go/
    │   ├── python/
    │   ├── rust/
    │   ├── shell/
    │   └── zig/
    └── workflows/
        └── architecture-review/
```

## References

- Main guide: `CODEX.md`
- Claude source material used for restoration lives under `../claude/skills/`, `../claude/agents/coder.md`, and `../claude/agents/devops-engineer.md`
