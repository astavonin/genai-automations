# Spec — <Article Title>

**Article:** <NNN-slug>
**Companion repo:** <repo-name>
**Issue:** [#N](URL)
**Status:** Draft | Approved

---

## 1. Scope

### In Scope

- ...

### Out of Scope

- ...

---

## 2. Functional Requirements

Observable behaviours the implementation must provide. No implementation detail.

- **FR1:** ...
- **FR2:** ...

---

## 3. Non-Functional Requirements

Constraints the implementation must satisfy.

- **NFR1:** ...
- **NFR2:** ...

---

## 4. Public API Contract

Types and their invariants. No method signatures, no implementation detail, no crate choices.

### `TypeName`

Invariants:
- ...

---

## 5. Test Requirements

### Unit Tests

Must run in CI without hardware, without network. Use mocks or fakes where needed.

| Test | Behaviour under test | Mock / fake needed |
|------|---------------------|-------------------|
| `test_name` | ... | ... |

### Integration Tests

Run against real infrastructure available in standard CI (e.g., vivid virtual device).

| Test | Behaviour under test | Requires |
|------|---------------------|---------|
| `test_name` | ... | vivid / ... |

### Hardware Tests

*(Deferred to article N — requires <dependency>)*
— or —
*(N/A — article does not require on-device validation)*

---

## Rules

- **`Draft` is what authoring produces; `/review-spec` is the only writer of `Approved`.** This entry states the rule for both spec templates; `APPENDIX-SPEC-TEMPLATE.md` points here rather than restating it, and reads "spec" below as its own page. `/spec` leaves the header at `Draft` however finished the spec reads, and an `APPROVED` `/review-spec` flips it; a review returning `CHANGES REQUESTED` or `REJECTED` clears an `Approved` it finds back to `Draft`. The field records a review rather than the author's own judgment that the work is done, which is what it recorded before that command existed. A spec still reading `Approved` from then is re-run through `/review-spec`, not grandfathered. The two values remain distinct from the review-gate marker `CLAUDE.md` §4 defines (`APPROVED | CHANGES REQUESTED | REJECTED`) — that marker lives in `spec-review.md`, and this field never carries one of its values. `tests/verify-workflow-safety.sh` scopes its gate to review files by explicit path rather than by scanning every `**Status:**` occurrence, so the two do not collide.
