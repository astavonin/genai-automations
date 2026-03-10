---
name: implement
description: Implement approved design using coder or devops-engineer agent
---

# Implementation Command

Implement the approved design following the chosen agent's expertise.

## Agent Selection

- **coder** (sonnet): Application code (C++, Go, Rust, Python)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure

## Skills Required

- languages/* (language-specific guidelines)
- domains/code-quality (code quality standards)
- domains/testing (testing strategies)

## Actions

0. Read skills for phase context:
   ```
   Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
   Read ~/.claude/skills/domains/code-quality/SKILL.md
   Read ~/.claude/skills/domains/testing/SKILL.md
   ```
   If using devops-engineer agent, also read:
   ```
   Read ~/.claude/skills/domains/devops/SKILL.md
   ```

1. Select appropriate agent based on task type
2. Write code following approved design
3. Include comprehensive unit tests (mandatory)
4. Verify build passes after each change
5. Follow language-specific style guides:
   - C++: C++ Core Guidelines
   - Python: PEP 8, Google Python Style Guide
   - Go: Effective Go, Code Review Comments
   - Rust: Rust API Guidelines
   - Zig: Zig Style Guide
6. Apply code formatting (clang-format, black, rustfmt, etc.)

## Output

Implementation complete with:
- Production code
- Comprehensive unit tests
- Passing build
- Applied formatting

## Usage

```
"I'll use coder agent to implement the authentication module following the approved design..."
```

```
"I'll use devops-engineer agent to create the CI pipeline configuration..."
```

## Next Step

After implementation, use `/review-code` for mandatory code review.
