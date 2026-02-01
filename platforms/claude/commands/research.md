---
name: research
description: Run research phase using architecture-research-planner agent
---

# Research Command

Investigate existing codebase patterns and architecture using the architecture-research-planner agent.

## Agent

**architecture-research-planner** (opus model)

## Skills Required

- languages/* (language-specific patterns)
- domains/architecture (architecture patterns)

## Actions

1. Investigate existing codebase patterns
2. Understand current architecture
3. Identify integration points and dependencies
4. Ask clarifying questions if requirements are unclear

## Output

**File:** `planning/<goal>/milestone-XX/design/<feature>-analysis.md`

**Contains:**
- Codebase analysis
- Architecture diagrams (Mermaid)
- Research findings
- Integration points
- Dependency analysis

## Usage

```
"I'll use architecture-research-planner agent to investigate [feature/area]..."
```
