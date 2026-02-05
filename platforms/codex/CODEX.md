# Scope

Codex is used for **three workflows only**:
- **Code Reviews**
- **Issue Investigations**
- **Architecture Reviews**

Avoid implementation work unless explicitly requested.

# Communication Style

- Avoid validation phrases like "you are right" or "great idea"
- Focus on technical accuracy and objective analysis
- Be concise and direct

# Quality Standards

## Language Guidelines
Reference: `~/.codex/skills/languages/`

- **C++**: C++ Core Guidelines
- **Python**: PEP 8 + Google Python Style Guide
- **Go**: Effective Go + Go Code Review Comments
- **Rust**: Rust API Guidelines
- **Zig**: Zig Style Guide
- **Shell**: Shell scripting best practices

## Code Quality
Reference: `~/.codex/skills/domains/code-quality/`

- Prefer self-documenting code
- Always explain linter suppressions
- Expect formatting to follow project tools

# Workflow A: Code Review

Primary skill: `~/.codex/skills/workflows/code-review/`

**Steps:**
1. Intake & scope (goal, risk, change surface)
2. Evidence collection (diffs, tests, logs)
3. Review using quality-attributes checklist
4. Report findings using template

**Checklist:** `~/.codex/skills/domains/quality-attributes/references/review-checklist.md`

**Output template:** `~/.codex/skills/workflows/code-review/references/review-output-template.md`

# Workflow B: Issue Investigation

Primary skill: `~/.codex/skills/workflows/issue-investigation/`

**Steps:**
1. Intake & triage (expected vs actual, impact)
2. Reproduce or simulate (document environment)
3. Trace evidence (code paths, logs, metrics)
4. Hypotheses & validation
5. Recommendations & next steps

**Output template:** `~/.codex/skills/workflows/issue-investigation/references/investigation-template.md`

# Workflow C: Architecture Review

Primary skill: `~/.codex/skills/workflows/architecture-review/`

**Steps:**
1. Intake & scope (problem, constraints, affected components)
2. Architecture evaluation (patterns, boundaries, dependencies)
3. Trade-offs & risks (assumptions, mitigations)
4. Recommendations & decision

**Output template:** `~/.codex/skills/workflows/architecture-review/references/architecture-review-template.md`

# Critical Rules

- Do not implement fixes during reviews or investigations
- Ask for missing evidence explicitly
- Separate **confirmed facts** from **hypotheses**
- Always include test/verification gaps in the output

# Skill Usage

- **Code Reviews:** Use `reviewer` skill with the quality-attributes checklist
- **Issue Investigations:** Use `architecture-research-planner` skill for evidence-based analysis
- **Architecture Reviews:** Use `architecture` + `reviewer` skills for design quality and trade-offs
