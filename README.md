# GenAI Automations

Personal collection of tools and processes for managing GenAI-related workflows.

## Tools

### glab-management

GitLab automation tool for managing epics and issues programmatically.

- Create issues from YAML definitions with dependency tracking
- Load and display issue/epic information in markdown
- Search issues and epics by text query

See [glab-management/](glab-management/) for details.

#### Requirements

- Python 3
- [glab CLI](https://gitlab.com/gitlab-org/cli)

## Agent Templates

Custom Claude agent configurations are defined under `~/.claude/agents/`. Each agent is scoped to a specific responsibility and enforces explicit quality constraints.

- The `coder.md` agent is used for systems programming in C++, Rust, Python, and Go. It enforces language-specific style guidelines such as the C++ Core Guidelines, PEP 8, and the Rust API Guidelines, with expectations around memory safety, algorithmic efficiency, and a minimum of 80% code coverage.

- The `devops-engineer.md` agent focuses on infrastructure, CI/CD pipelines, and containerization. It emphasizes local-CI parity, efficient resource usage, and a smooth developer experience.

- The `architecture-research-planner.md` agent handles system design and documentation. It prioritizes concise visual artifacts over prose, producing Mermaid diagrams with a preference for the C4 model.

Codex skills mirror these agents for task-specific triggers in `~/.codex/skills/` (coder, devops-engineer, architecture-research-planner, writer).

General Claude behavior and coding guidelines live in `~/.claude/CLAUDE.md`.
