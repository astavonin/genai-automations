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

## Architecture Documentation

Use Mermaid for all architecture diagrams. Prefer: Architecture, Sequence, State, and Class diagrams. See `references/diagrams.md` for full examples.

**Diagram types:**
- **Component** — system structure and service relationships
- **Sequence** — interaction flows and timing
- **State** — state machines and transitions
- **C4-style** — system context with external actors

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

## Architecture Reviews

- Does it solve the stated problem?
- Is it the simplest approach?
- Are trade-offs understood?
- Is it consistent with existing patterns?
- Can it evolve as requirements change?

## References

See `references/` directory for:
- Mermaid diagram examples (`diagrams.md`)
