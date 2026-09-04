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

## Change Class

**How much rigor a change owes is not constant. It scales with what being wrong costs and with what fixing it costs.** Designing a CI job to the standard of a shipped library wastes the effort; designing a shipped library to the standard of a CI job ships the defect to a customer.

Classify every change before designing it. One of four values, recorded in `analysis.md` under `## Change Class` and in the design doc header as `**Class:**`. It calibrates the design's depth, the test volume, and the severity a reviewer assigns.

| Class | Covers | Being wrong costs | Fixing it costs |
|---|---|---|---|
| `CI` | build, CI/CD, tooling, dev scripts, automation | a red pipeline the author sees in minutes | one commit — no consumer to migrate |
| `TEST` | test code, harnesses, fixtures, test infrastructure | a test that misleads, or one costing more to maintain than it catches | one commit |
| `PRODUCT-NEW` | production code nothing outside the repo depends on yet | a real defect, on an interface nobody has built against | the fix, plus a free interface change |
| `PRODUCT-SHIPPED` | production code already released to a customer or depended on by another team | a defect in somebody's running system | the fix, a release, and every consumer that must keep working |

### What each class demands

**`CI` — design the path that runs; do not engineer against the improbable.** Cover every failure the job is documented to produce, starting with the ones that would pass silently — a red pipeline announces itself, so the silent failure is the one to reach for first, not the only one worth reaching for. An occasional failure here is acceptable: it is loud, cheap, and re-runnable, and the retry costs less than the mechanism that would have prevented it. Do not add a fallback, a cache, or a recovery path for a condition that has never occurred. Flakiness that *masks* a real failure is a different thing and this allowance does not cover it.

**`TEST` — cover the real paths, stop at the hypothetical ones.** Every test is a permanent support cost: read on each failure, rewritten on each refactor. Cover the paths the code actually takes and each failure it is documented to produce. A scenario whose setup costs more than the scenario is worth — one needing elaborate scaffolding, a fake of a fake, or a production rewrite to become reachable — is a scenario to record as uncovered, not to test. Volume is not coverage.

**`PRODUCT-NEW` — consider every possibility; owe nothing to the past.** Every failure mode of every path is in scope: invalid input, dependency failure, boundary, concurrency, partial write. Compatibility is not. The API, schema, wire format, and on-disk layout may all change, so design the right shape rather than a compatible one — no shim, no deprecation window, no version negotiation. A design carrying one owes an explanation of who is already depending on it.

**`PRODUCT-SHIPPED` — everything `PRODUCT-NEW` demands, plus what is already deployed.** Name the compatibility surface: public API, wire format, persisted data, config and CLI flags. For each, state whether this change preserves it; where it does not, state the migration path and the deprecation window. A behavioural change no existing caller can opt out of is a trade-off for §7, not an implementation detail.

### Choosing between them

- The order, low to high: `CI` < `TEST` < `PRODUCT-NEW` < `PRODUCT-SHIPPED`. "Highest" below means furthest right in that order.
- The class is the **highest** one the change touches. A CI job edited alongside a shipped library is `PRODUCT-SHIPPED`.
- `PRODUCT-NEW` versus `PRODUCT-SHIPPED` turns on whether anything **outside this repo already depends on it** — released to a customer, consumed by another team, or persisted on a device in the field. Pre-release code with internal callers only is `PRODUCT-NEW`.
- Where two classes are genuinely arguable, ask the user. Do not average them.

## Design Trade-offs

The class above sets the budget; these set the direction within it.

| Trade-off | Guidance |
|---|---|
| Performance vs. Maintainability | Optimize only when necessary; profile first |
| Flexibility vs. Simplicity | YAGNI — don't add features for hypothetical future needs |
| Abstraction vs. Concreteness | Three instances before abstracting |

## Required Design Doc Sections

Design docs follow the 8-section template at `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md`:

1. Problem Statement
2. Goals and Non-Goals
3. Implementation Context
4. Architecture Overview (Mermaid diagram required)
5. Detailed Design (component boundaries and interfaces — not implementations)
6. Test Requirements (unit, integration, E2E — the behaviours and failure modes to cover, not file names)
7. Trade-offs and Alternatives *(omit with a one-line note if none)*
8. Open Questions *(omit with a one-line note if none)*

Files-changed tables are **not** part of design docs — they emerge during implementation. §6 states what must be covered and at which level; the tests themselves are written during implementation.

Documents written to the older 7-section numbering, with Trade-offs at §6 and Open Questions at §7, still exist. `doc-metrics` matches its length targets by heading content rather than by number, so those documents are scored against the same slots — but new documents use the numbering above.

## Architecture Reviews

- Does it solve the stated problem?
- Is it the simplest approach?
- Are trade-offs understood?
- Is it consistent with existing patterns?
- Can it evolve as requirements change?

## References

See `references/` directory for:
- Mermaid diagram examples (`diagrams.md`)
