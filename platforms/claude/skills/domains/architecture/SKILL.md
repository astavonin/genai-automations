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

Every design doc must include a **Test Plan** section before it can be reviewed. Template:

```markdown
## Test Plan

### Unit Tests
| Component / behavior | Scenarios |
|----------------------|-----------|
| Foo.bar              | valid input, nil arg, error return |

### Integration Tests
| Boundary             | What it verifies |
|----------------------|-----------------|
| FooService ↔ DB      | persists record, unique constraint enforced |

### Explicitly not tested
- <what and why>
```

Rules:
- Every public function/method must appear in Unit Tests or have an explicit exclusion with reason
- Every component boundary touching external systems must appear in Integration Tests
- "Explicitly not tested" must be non-empty only when there is a genuine reason (third-party owned, out of scope); leaving it empty signals completeness

## Architecture Reviews

- Does it solve the stated problem?
- Is it the simplest approach?
- Are trade-offs understood?
- Is it consistent with existing patterns?
- Can it evolve as requirements change?

## References

See `references/` directory for:
- Mermaid diagram examples (`diagrams.md`)
