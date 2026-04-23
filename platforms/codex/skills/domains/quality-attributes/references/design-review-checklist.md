# Design And Workflow Review Checklist

Use this checklist for the narrowed Codex scope: design documents, architecture proposals, workflow designs, and command/interface docs.

## 1. Problem And Scope

- [ ] The problem being solved is stated explicitly.
- [ ] The proposed change is scoped clearly.
- [ ] Assumptions, non-goals, and out-of-scope items are visible.
- [ ] Existing constraints or dependencies are named.

## 2. Interface And Contract Completeness

- [ ] Entry points are explicit.
- [ ] Required request fields are explicit.
- [ ] Outputs are explicit.
- [ ] Writable paths or mutation rules are explicit.
- [ ] Canonical examples or templates are present when the interface is non-trivial.
- [ ] Inputs supplied indirectly through files are still made visible from the user-facing workflow section.

## 3. Consistency Pass For Introduced Fields

- [ ] Every required field appears in the request or interface section.
- [ ] Every required field appears in the user-facing workflow or command entry section in a way that makes the real interface understandable.
- [ ] Every required field appears in the runtime behavior section when relevant.
- [ ] Every required field appears in the validation or failure section when relevant.
- [ ] Every required field appears in the canonical template or worked example.
- [ ] Every required path, file, flag, or artifact is used consistently across the document.
- [ ] Each hard invariant is traceable from contract to runtime behavior to enforcement.
- [ ] Missing propagation is treated as an interface defect, not just an editorial gap.

## 4. Invariants And Enforcement

- [ ] Hard invariants are stated clearly.
- [ ] Each hard invariant names an enforcement mechanism.
- [ ] Advisory guidance is not described as if it were enforced.
- [ ] Failure behavior is defined when an invariant is violated.

## 5. Quality Attributes

### Supportability
- [ ] Troubleshooting expectations are described where relevant.
- [ ] Error reporting or operator feedback is described where relevant.

### Extendability
- [ ] The design can evolve without unnecessary rework.
- [ ] Extension points or future boundaries are identified only when justified.

### Maintainability
- [ ] The design is understandable and not over-engineered.
- [ ] Terminology is consistent across the document.

### Testability
- [ ] Validation or verification approach is described.
- [ ] Important scenarios, edge cases, or failure modes are identified.

### Performance
- [ ] Performance or scale implications are acknowledged when relevant.

### Safety
- [ ] Failure modes and edge cases are called out explicitly.
- [ ] Destructive or state-changing behavior is bounded clearly.

### Security
- [ ] Trust boundaries, input validation, or path constraints are defined when relevant.

### Observability
- [ ] The design explains how behavior or failures can be observed when relevant.

## 6. Human Readability

- [ ] The document explains the change before diving into low-level structure.
- [ ] Tables, examples, and diagrams reduce explanation cost rather than add noise.
- [ ] Workflow or lifecycle designs include a diagram when it materially helps.
- [ ] The document reads cleanly without requiring schema-first interpretation.

## 7. Review Output Expectations

- [ ] Findings are prioritized over summary text.
- [ ] Confirmed issues are separated from open questions or missing evidence.
- [ ] Recommendations are concrete and tied to the design, not generic advice.

## Severity Guidance

| Level | Meaning |
|---|---|
| `critical` | The design is unsafe, inconsistent, or cannot meet a required constraint as written. |
| `major` | A significant gap exists in interface definition, enforcement, or quality attributes. |
| `minor` | The design is basically workable but needs clarification or tightening. |
| `suggestion` | Optional improvement that is not required for correctness. |
