# Review Checklist

Use this checklist when conducting design and architecture reviews in the narrowed Codex scope.

## Contents

1. Context
2. Problem and scope
3. Interface and contract completeness
4. Introduced-field consistency
5. Invariants and enforcement
6. Quality attributes
7. Human readability
8. Review output and severity

## Design Review Checklist

### 1. Context

- [ ] The requirement, issue, or decision under review is explicit.
- [ ] Existing system constraints, dependencies, and integration points are identified.
- [ ] Assumptions, non-goals, and out-of-scope items are visible.

### 2. Problem And Scope

- [ ] The problem being solved is stated clearly.
- [ ] The proposed change is scoped clearly.
- [ ] The design explains why this approach is being taken now.

### 3. Interface And Contract Completeness

- [ ] Entry points are explicit.
- [ ] Required request fields or inputs are explicit.
- [ ] Outputs and produced artifacts are explicit.
- [ ] Writable paths or mutation rules are explicit.
- [ ] Canonical examples or templates are present when the interface is non-trivial.
- [ ] Inputs supplied indirectly through files are still visible from the user-facing workflow section.

### 4. Consistency Pass For Introduced Fields

- [ ] Every required field appears in the request or interface section.
- [ ] Every required field appears in the user-facing workflow or command entry section.
- [ ] Every required field appears in runtime behavior when relevant.
- [ ] Every required field appears in validation or failure behavior when relevant.
- [ ] Every required field appears in the canonical template or worked example.
- [ ] Every required path, file, flag, or artifact is used consistently across the document.
- [ ] Each hard invariant is traceable from contract to runtime behavior to enforcement.
- [ ] Missing propagation is treated as an interface defect, not just an editorial gap.

### 5. Invariants And Enforcement

- [ ] Hard invariants are stated clearly.
- [ ] Each hard invariant names an enforcement mechanism.
- [ ] Advisory guidance is not described as if it were enforced.
- [ ] Failure behavior is defined when an invariant is violated.

### 6. Quality Attributes

#### Supportability
- [ ] Troubleshooting expectations are described where relevant.
- [ ] Error reporting or operator feedback is described where relevant.
- [ ] Fallible or blocking cleanup has an explicit observable shutdown path and defined fallback behavior.
- [ ] Background work, retries, timeouts, degraded operation, and final failure are diagnosable.

#### Extendability
- [ ] The design can evolve without unnecessary rework.
- [ ] Extension points or future boundaries are identified only when justified.
- [ ] The abstraction level is appropriate for likely change.
- [ ] Source, binary, wire, storage, configuration, CLI, feature, toolchain, and platform compatibility commitments are explicit where relevant.
- [ ] Breaking changes define deprecation, migration, or rollout behavior.

#### Maintainability
- [ ] The design is understandable and not over-engineered.
- [ ] Terminology is consistent across the document.
- [ ] The design aligns with existing repository or system patterns unless divergence is justified.
- [ ] No equivalent helper or abstraction already exists in the repository or expected ecosystem libraries; the design explains any necessary custom abstraction.
- [ ] New dependencies and build-time extensions have ownership, maintenance, security, license, reproducibility, toolchain, and target implications addressed.

#### Testability
- [ ] Validation or verification approach is described.
- [ ] Important scenarios, edge cases, or failure modes are identified.
- [ ] Validation guards identify independently rejected classes defined by different rules, branches, invariants, or policy reasons without inventing categories the boundary cannot represent.
- [ ] The design includes a concrete test plan when implementation is expected.
- [ ] The test plan covers all public API paths affected by the change.
- [ ] The test plan includes each distinct failure mode for public functions or methods that can fail.
- [ ] The test plan includes negative tests for each distinct validation behavior behind an allowlist, blocklist, or range check and valid boundary tests where applicable.
- [ ] Behavioral correctness scenarios are called out explicitly: wrong output, data corruption, silent invalid-input acceptance, liveness violations, and security or correctness invariant bypasses.
- [ ] When a coverage target can be extracted from repository policy, CI, or the surrounding context, the expected minimum is stated and is `>= 80%` unless a stricter project rule exists.
- [ ] The design explains what can be tested locally or in containerized environments.
- [ ] The design calls out blockers for real-environment, hardware, or credentialed testing when relevant.
- [ ] The design describes whether manual verification is straightforward or operationally difficult.

#### Performance
- [ ] Performance or scale implications are acknowledged when relevant.
- [ ] Obvious bottlenecks or resource risks are considered when relevant.

#### Safety
- [ ] Failure modes and edge cases are called out explicitly.
- [ ] Error handling level is justified: preventable failures are avoided up front, and recovery or reporting happens at the first layer with enough context.
- [ ] Destructive or state-changing behavior is bounded clearly.
- [ ] Recovery or fallback behavior is described when relevant.
- [ ] Fallible cleanup, partial success, timeout, cancellation, retry, and background failure have explicit semantics.
- [ ] Tasks, threads, workers, queues, buffers, retries, and in-flight operations are bounded and define backpressure, failure propagation, and shutdown order.
- [ ] Language and runtime constraints are stated as design contracts for failure channels, lifecycle, concurrency, cancellation, unsafe or foreign boundaries, and cleanup.
- [ ] The design leaves exact language constructs to implementation unless a construct is itself required to enforce or expose the contract.

#### Security
- [ ] Trust boundaries, input validation, or path constraints are defined when relevant.
- [ ] Secret handling, auth, or privilege assumptions are described when relevant.

#### Observability
- [ ] The design explains how behavior or failures can be observed when relevant.
- [ ] Logging, metrics, or trace expectations are described when relevant.

### 7. Human Readability

- [ ] The document explains the change before diving into low-level structure.
- [ ] Tables, examples, and diagrams reduce explanation cost rather than add noise.
- [ ] Workflow or lifecycle designs include a diagram when it materially helps.
- [ ] The document reads cleanly without requiring schema-first interpretation.

### 8. Review Output Expectations

- [ ] Findings are prioritized over summary text.
- [ ] Confirmed issues are separated from open questions or missing evidence.
- [ ] Recommendations are concrete and tied to the design, not generic advice.
- [ ] Any finding that identifies incorrect runtime behavior includes a `Required test:` line describing the triggering input or precondition and the asserted outcome.

## Severity Guidance

| Level | Meaning |
|---|---|
| `Critical` | The design is unsafe, internally contradictory, or cannot meet a required constraint as written. |
| `High` | A significant correctness, security, interface, enforcement, or quality-attribute gap must be resolved before approval. |
| `Medium` | The design is workable but has a material clarity, supportability, testability, or consistency gap that must be resolved before approval. |
| `Low` | Non-blocking improvement that does not affect correctness or approval. |
