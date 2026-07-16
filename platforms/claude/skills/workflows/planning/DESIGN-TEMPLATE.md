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

**Functional Requirements:**
- ...

**Non-Functional Requirements:**
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

**On-Device Verification:** *(MANDATORY when the feature is device-verifiable and the project has documented device procedures. A feature is device-verifiable when the task, acceptance criteria, changed code path, CI/HIL job, verifier script, or project guidance makes target hardware or device/HIL validation relevant. Omit with a one-line note containing the explicit tag `on-device scope: NO` only after checking those sources — e.g., "On-Device Verification: N/A — feature is software-only (on-device scope: NO)." A note without this tag is treated as ambiguous by the reviewer.)*

*Derive from the project's `CLAUDE.md`, `README.md`, or existing planning docs. Do not invent steps — only include procedures that are known for this project's device.*

**Entry point:** `<script-or-make-target>` — the single command humans and CI invoke (e.g. `make verify-device`, `scripts/verify-device.sh`, `./dev.sh test-device`). Must already exist in the repo or be listed as a deliverable of this feature.

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

**CI integration:** *(how CI triggers on-device verification when no local device is available — e.g., `DEVICE_IP` env var, a runner label/tag, a dedicated CI job name, or a webhook trigger. Omit with a one-line note if CI device testing is not configured for this project.)*

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

## 6. Test Requirements

### Unit Tests
*(Single-component tests with collaborators mocked or stubbed. List the specific behaviours and failure modes that must be covered — not file names.)*
- ...

### Integration Tests
*(Component-boundary tests that cross at least one real dependency — database, filesystem, IPC, network call. List the interaction paths that must be exercised.)*
- ...

### E2E Tests
*(System- or user-flow-level tests that exercise the feature end-to-end. Omit with a one-line note if the feature has no user-facing or cross-service flow.)*

*(Omit E2E subsection with a one-line note if no E2E tests are required for this feature)*

---

## 7. Trade-offs and Alternatives

### Option A — <Chosen Approach>
**Pros:** ...
**Cons:** ...

### Option B — <Alternative>
**Pros:** ...
**Cons:** ...

**Decision:** Chose A because …

*(Omit section with a one-line note if there are genuinely no alternatives)*

---

## 8. Open Questions

*(None — omit this section or list specific open questions as `- [ ] <question>` items)*
