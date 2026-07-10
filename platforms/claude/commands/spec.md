---
name: spec
description: Produce a coding specification for an article — scope, functional/non-functional requirements, public API contract, and unit/integration test requirements. Phase 1 of the article authoring workflow.
---

# Spec Command

Produce a coding specification for the current article issue. The spec defines the **contract** for the implementation — what must be observable, not how to achieve it. It is the document that `/review-article` Pass 1 validates the implementation against.

## Agent

**architecture-research-planner (opus)** — spec writing must be delegated to this agent. Never write or edit spec files inline with Write/Edit tools.

## Actions

### Step 0: Read context

```
Read ~/.claude/skills/workflows/planning/SPEC-TEMPLATE.md
Read CLAUDE.local.md                         # companion repos table + technical familiarity
cat planning/progress.md                     # identify active issue + folder
cat planning/book/milestone-XX-<name>/status.md   # article notes for this issue
```

Also read `planning/book/milestone-XX-<name>/issues/<NNN-name>/analysis.md` if it exists.

If `planning/book/todos.md` exists, read it and extract all open entries where `Resolves in` contains the current article slug or number. These are cross-article items registered to be closed by this article — pass them to the agent in Step 3 as additional requirements context with instruction: "These open TODOs must be resolved by this article — incorporate their resolution as Functional Requirements, Non-Functional Requirements, or Test Requirements in the appropriate spec sections. Do not list them as a separate TODO section."

### Step 1: Locate companion repo

From `CLAUDE.local.md` companion repos table, resolve the local path for the current article's part. Confirm the directory exists before proceeding. If the path does not exist, stop and ask the user.

### Step 2: Q&A (short — only for genuine ambiguity)

Read the article notes from `status.md`. If the scope and behaviours are clear enough to write the spec without clarification, skip directly to Step 3 and say "No questions — proceeding to spec."

If clarification is needed, ask at most 2–3 questions, one at a time. Ask only when:
- The in/out of scope boundary is genuinely ambiguous from the article notes
- Whether a behaviour is testable without hardware is unclear (unit vs. integration boundary)
- Whether a type is new or modifies an existing contract is unclear

### Step 3: Spawn architecture-research-planner

Declare: "I'll use architecture-research-planner agent to write the spec..."

Pass to the agent:
- The article notes from `status.md` for this issue
- The analysis.md content (if it exists)
- The companion repo local path and instruction to read all relevant source files before writing
- The full SPEC-TEMPLATE.md structure (all 5 sections required)
- Any Q&A answers from Step 2

**Agent instructions:**

1. Read all relevant source files in the companion repo first. Identify what currently exists vs. what is new or modified.
2. Write `planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md` following the template exactly.

**Section rules to enforce:**

- **Scope (§1):** Both lists must be explicit. Out of scope must name things a reader might reasonably expect to be included but aren't.
- **Functional Requirements (§2):** Observable outputs and side effects only. No implementation choices, no crate names, no "use X pattern." Each FR must be independently verifiable.
- **Non-Functional Requirements (§3):** Hard constraints — safety flags, performance bounds, compile targets, dependency rules, runtime restrictions. Phrased as pass/fail, not aspirations.
- **Public API Contract (§4):** Types and their invariants. No method signatures, no crate choices. State what the type guarantees, not how it does it.
- **Test Requirements (§5):**
  - Unit tests: runnable in CI without hardware and without network; mocks/fakes allowed; one row per test case
  - Integration tests: require real-but-accessible infrastructure (vivid virtual device, local socket, etc.); one row per test case
  - Hardware tests: always deferred unless the article is explicitly about on-device testing; state which article they belong to and what dependency blocks them

### Step 4: Post-write

1. Ask the user if they want to `open <path>` the spec file.
2. Push planning to backup:
   ```
   Read ~/.claude/skills/workflows/push-planning/SKILL.md
   ```

## Output

**File:** `planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md`

**Contains:**
- Header (article, repo, issue, status)
- §1 Scope — in / out of scope (explicit lists)
- §2 Functional Requirements
- §3 Non-Functional Requirements
- §4 Public API Contract (types + invariants)
- §5 Test Requirements (unit, integration, hardware)

## Next Step

After the spec is correct, the user implements in the companion repo (Phase 2), then `/write` produces the article draft (Phase 3).
