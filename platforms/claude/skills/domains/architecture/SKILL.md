---
name: architecture
description: Software architecture patterns and documentation practices. Use when designing systems, creating architecture docs, or reviewing design proposals to apply separation of concerns, modularity, and Mermaid diagrams.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: domains
  tags: [architecture, design, diagrams, mermaid]
---

# Architecture Skill

Software architecture patterns, design principles, and documentation practices.

## Core Principles

### Separation of Concerns
- Each module has a single, well-defined responsibility
- Clear boundaries between components
- Minimize coupling between modules

### Modularity
- Components can be understood independently
- Well-defined interfaces
- Easy to replace or upgrade components

### Abstraction Levels
- Appropriate abstraction for the problem domain
- Not over-engineered, not under-abstracted

### Dependency Management
- Minimize dependencies
- Depend on abstractions, not concretions
- Use dependency injection where appropriate

## Code in Design Documents

**Only tiny illustration snippets or pseudocode are allowed in design docs.**

- Pseudocode must show intent, not syntax — language keywords and real APIs are not required
- Real code snippets: max ~5 lines, only to illustrate a non-obvious interface or contract
- No full function bodies, no complete class definitions, no working implementations
- If you feel you need more than 5 lines of real code to explain a design decision, use a diagram instead

```
// ALLOWED — pseudocode illustrating flow
connect(addr) → retry loop → backoff → emit Connected event

// ALLOWED — tiny interface sketch
type Handler interface { Handle(ctx, msg) error }

// NOT ALLOWED — full implementation in a design doc
func (h *handler) Handle(ctx context.Context, msg Message) error {
    if err := h.validate(msg); err != nil { ... }
    ...
}
```

## Architecture Documentation

Use Mermaid for all architecture diagrams. Always use `<br/>` for line breaks inside node labels — never `\n`.

**Which diagram to use:**

| Situation | Diagram type |
|-----------|-------------|
| System structure, service relationships | Component (`graph TD/TB`) |
| Interaction flows, timing, call sequences | Sequence (`sequenceDiagram`) |
| State machines, lifecycle transitions | State (`stateDiagram-v2`) |
| System context with external actors | C4-style (`graph TB` with subgraph) |

**Rules:**
- Every design doc must include at least one diagram
- Split large systems into multiple focused diagrams — one diagram per concern
- Use consistent naming across all diagrams in the same document
- Add notes for non-obvious relationships
- Prefer the diagram types above; use flowcharts only as a last resort
- `<br/>` is supported in node labels but NOT in edge labels (`|...|`); `()` and `{}` are also special shape syntax and cannot appear unescaped in edge labels

**Validation (mandatory after every diagram write or edit):**
Call `mcp__claude_ai_Mermaid_Chart__validate_and_render_mermaid_diagram` with the diagram code. Check that `valid: true` before moving on. Do not skip this step even for small edits — silent parse errors (e.g. `<br/>` in edge labels) render invisible to the author but break the diagram for every reader.

See `references/diagrams.md` for copy-paste examples of each type.

## Common Patterns

### Layered Architecture
- Presentation → Business logic → Data access
- Clear dependencies (top-down only)

### Event-Driven Architecture
- Producers and consumers, asynchronous communication, loose coupling

### Microservices
- Independent deployments, service boundaries by domain, API contracts

### Plugin Architecture
- Core system with extension points, isolation between plugins

## Design Trade-offs

| Trade-off | Guidance |
|---|---|
| Performance vs. Maintainability | Optimize only when necessary; profile first |
| Flexibility vs. Simplicity | YAGNI — don't add features for hypothetical future needs |
| Abstraction vs. Concreteness | Three instances before abstracting |

## Required Design Doc Sections

Design docs follow the 7-section template at `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md`:

1. Problem Statement
2. Goals and Non-Goals
3. Implementation Context
4. Architecture Overview (Mermaid diagram required)
5. Detailed Design (component boundaries and interfaces — not implementations)
6. Trade-offs and Alternatives *(omit with a one-line note if none)*
7. Open Questions *(omit with a one-line note if none)*

Test plans and files-changed tables are **not** part of design docs — they emerge during implementation.

## Architecture Reviews

- Does it solve the stated problem?
- Is it the simplest approach?
- Are trade-offs understood?
- Is it consistent with existing patterns?
- Can it evolve as requirements change?

## References

See `references/` directory for:
- Mermaid diagram examples (`diagrams.md`)
