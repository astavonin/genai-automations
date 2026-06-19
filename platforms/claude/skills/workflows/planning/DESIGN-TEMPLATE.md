# Design — <Feature Name>

**Goal:** `<goal-folder-name>`
**Milestone:** `milestone-XX-<name>` · `%N`
**Feature:** `#N`
**Branch:** `feature/<branch-name>`
**Status:** Draft | Approved | Superseded
**Revision:** 1

---

## 1. Problem Statement

What problem does this solve? Why now?

---

## 2. Goals and Non-Goals

### Goals
- ...

### Non-Goals
- ...

---

## 3. Implementation Context

**Repository:** `/absolute/path/to/repo`

**Requirements:**
- ...

**Constraints:**
- ...

**Verification:**

*Extract from the project's `README.md` or `CLAUDE.md`. Must cover all three workflows.*

```bash
# Build / compile
<command>

# Test
<command>

# Debug / run
<command>
```

**On-Device Verification:** *(MANDATORY when the feature's final goal is on-device execution and the project has documented device procedures; omit with a one-line note otherwise)*

*Derive from the project's `CLAUDE.md`, `README.md`, or existing planning docs. Do not invent steps — only include procedures that are known for this project's device.*

```bash
# Build test package (MANDATORY when verification requires a special artifact — OTA image,
# firmware bundle, test APK, etc.; omit with a one-line note if a standard build suffices)
<command>

# Deploy to device
<command>

# Verify on device
<command>
```

Expected outcome on device:
- ...

Failure indicators (what to check if verification does not pass):
- ...

**Context Files:**
- `path/to/file`

---

## 4. Architecture Overview

```mermaid
...
```

Brief narrative explaining the diagram (3–5 sentences max).

---

## 5. Detailed Design

Describe component boundaries, interfaces, and contracts — not implementations.
Focus on: what each component is responsible for, how components communicate,
and any non-obvious invariants. Avoid method signatures, pseudocode, and file-level detail.

*(Feature-specific subsections — add as needed)*

---

## 6. Trade-offs and Alternatives

### Option A — <Chosen Approach>
**Pros:** ...
**Cons:** ...

### Option B — <Alternative>
**Pros:** ...
**Cons:** ...

**Decision:** Chose A because …

*(Omit section with a one-line note if there are genuinely no alternatives)*

---

## 7. Open Questions

- [ ] ...

*(Omit section with a one-line note if none)*
