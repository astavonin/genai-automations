# Spec — <Article Title>

**Article:** <NNN-slug>
**Companion repo:** <repo-name>
**Issue:** #N
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
