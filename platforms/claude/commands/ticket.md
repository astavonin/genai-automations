---
name: ticket
description: Create milestones, epics, and/or issues as YAML for projctl create
---

# Ticket Command

Generate a YAML definition for new milestones, epics, and/or issues, then create them via `projctl create`.

## Prerequisites

- `projctl` installed and configured
- Config has `gitlab.default_group` and `labels.default` set

## Workflow

### 1. Clarify Scope

If the user's request is ambiguous, ask:
- What level to create: milestone only, epic only, issues only, or a combination?
- For epics: new epic or add issues to an existing epic?
- For issues: which epic do they belong to (new or existing `&N`)?

Do NOT guess — ask before generating YAML.

### 2. Load Context (if referencing existing tickets)

If the user references an existing epic or milestone, load it first:

```bash
projctl load epic <epic_id>         # verify epic exists and get its title/description
projctl load milestone <milestone_id>  # verify milestone exists
```

### 3. Generate YAML

Save the YAML to `planning/<goal>/milestone-XX-<name>/tickets.yaml`.

Determine the path from the active milestone context (check `planning/progress.md` if not clear from the user's request). Ask the user to confirm the path if ambiguous.

**Full structure (use only the sections needed):**

```yaml
# ── MILESTONE (optional) ──────────────────────────────────────────
milestone:
  title: "Milestone Title"
  description: "What this milestone delivers"

# ── EPIC (required unless creating a standalone milestone) ─────────
epic:
  # Option A: link to existing epic
  id: 12  # IID of existing epic

  # Option B: create new epic
  # title: "Epic Title"
  # description: "Epic description"
  # labels: ["type::epic"]  # merged with config defaults

# ── ISSUES (required unless creating milestone/epic only) ──────────
issues:
  - id: "task-1"          # optional YAML-local ID for dependency tracking
    title: "Issue Title"
    weight: 8               # REQUIRED — hours; minimum 8 (one day); see weight estimation rules below
    description: |
      # Description
      What needs to be done and why.

      # Acceptance Criteria
      - Criterion 1
      - Criterion 2
    labels: ["priority::high"]  # optional, merged with config defaults
    assignee: "username"        # optional, GitLab username
    milestone: "Milestone Title" # optional, title (not ID)
    dependencies: []            # optional, see dependency formats below
```

**Dependency formats (mix freely):**

| Format | Meaning |
|--------|---------|
| `"task-1"` | YAML-local ID (issue in this same file) |
| `123` | GitLab IID (integer) — existing issue |
| `"#123"` | GitLab IID (string with `#` prefix) |

### 4. Description Templates

**Issue description (required sections):**

```markdown
# Description

Explain **what needs to be done** and **why it matters**.
Include background context, related problems, or dependencies if relevant.

---

# Acceptance Criteria

- <clear, measurable, testable criterion>
- <clear, measurable, testable criterion>

---

# Additional Notes (optional)

Add any references, related Epics, Issues, links, or notes for reviewers.
```

**Epic description — OMIT `# Acceptance Criteria` entirely:**

```markdown
# Description

Explain **what needs to be done** and **why it matters**.

---

# Additional Notes (optional)

Add any references, related issues, or notes.
```

**Quality rules:**
- Descriptions answer WHAT and WHY, not HOW
- Acceptance criteria are testable (can be verified as done/not done)
- Titles are concise, under 70 characters
- Avoid implementation details in descriptions — those belong in MR descriptions

### 5. Weight Estimation Rules

`weight` = hours of work. **Minimum is 8 (one full day).** Never use a round placeholder — always reason through the estimate.

**Assume LLM-assisted development:** code generation, boilerplate, docs, and test scaffolding are significantly accelerated. Estimate for a developer working with an LLM co-pilot, not alone.

**Reference scale:**

| Weight | Meaning | Typical task shape |
|--------|---------|-------------------|
| 8 | 1 day | Single well-scoped change, clear acceptance criteria, low unknowns |
| 16 | 2 days | Moderate complexity, some design decisions, straightforward testing |
| 24 | 3 days | Multiple components, non-trivial integration, or significant test coverage needed |
| 40 | 1 week | **Stop — see rule below** |

**40h rule — NEVER create a 40h issue.** If your estimate reaches 40h, stop and do one of:
1. **Split the issue** into 2–4 smaller issues (each ≤ 24h), each with its own acceptance criteria
2. **Propose a new epic** if the scope is large enough to warrant separate tracking, then create issues under it

Always present the split/epic proposal to the user and get confirmation before writing YAML.

**Estimation checklist — for each issue, ask:**
1. How many distinct components/files need to change?
2. Is there design ambiguity that requires exploration?
3. How much test coverage is expected (unit + integration)?
4. Are there external dependencies (APIs, schema migrations, config changes)?
5. Does it require review cycles or coordination?

**LLM acceleration factors (reduce raw estimate by these):**
- Boilerplate / CRUD code: −50%
- Test scaffolding: −40%
- Documentation: −60%
- Novel algorithms or debugging unknown systems: no reduction

**Example reasoning:**
> "Add REST endpoint for user preferences — CRUD handler, validation, unit tests. With LLM: handler ~2h, validation ~1h, tests ~2h, review ~1h → 6h → round up to 8 (minimum)."

> "Refactor auth middleware to meet compliance requirements — cross-cutting, affects 8 files, needs integration tests, security review. With LLM: 2 days implementation + 1 day testing/review → 24."

### 6. Show YAML for Verification

Display the file:
```bash
cat planning/<goal>/milestone-XX-<name>/tickets.yaml
```

Ask the user if they want to `open planning/<goal>/milestone-XX-<name>/tickets.yaml`, then wait before continuing.

### 7. Dry Run

Always run dry-run first:
```bash
projctl create --dry-run planning/<goal>/milestone-XX-<name>/tickets.yaml
```

Show the output. If anything looks wrong, stop and ask the user.

### 8. Create Tickets

After explicit user confirmation:
```bash
projctl create planning/<goal>/milestone-XX-<name>/tickets.yaml
```

Show the created issue/epic/milestone URLs. Ask if the user wants to `open <url>` for any of them.

## Critical Rules

1. **Ask before generating** — clarify scope if the user's intent is ambiguous
2. **Load existing tickets first** — always verify referenced epics/milestones exist
3. **Required sections** — every issue description must have `# Description` and `# Acceptance Criteria`
4. **YAML file first** — always write `planning/<goal>/milestone-XX-<name>/tickets.yaml` before running any projctl command
5. **Dry run before create** — always run `--dry-run` and show output; wait for confirmation
6. **Never guess labels** — use only labels known from config or explicitly provided by the user
7. **User confirmation required** — do NOT run `projctl create` without explicit approval after dry-run review

## Examples

### Add issues to existing epic

```yaml
epic:
  id: 37

issues:
  - title: "Research caching strategies"
    weight: 2
    description: |
      # Description
      Investigate caching options for the API response layer.

      # Acceptance Criteria
      - At least 3 strategies evaluated
      - Trade-offs documented in design doc
    labels: ["type::research"]
```

### New epic with issues under existing milestone

```yaml
epic:
  title: "User Preferences"
  description: "Allow users to configure notification and display settings"

issues:
  - id: "prefs-api"
    title: "Preferences API endpoint"
    weight: 3
    description: |
      # Description
      Implement REST endpoint for reading and writing user preferences.

      # Acceptance Criteria
      - GET /preferences returns current settings
      - PUT /preferences validates and persists changes
      - Unit tests cover happy path and validation errors

  - id: "prefs-ui"
    title: "Preferences settings page"
    weight: 2
    description: |
      # Description
      Build the UI page for managing user preferences.

      # Acceptance Criteria
      - Page renders current preferences
      - Changes are saved on submit
      - Error states are handled
    dependencies: ["prefs-api"]
```

### Milestone with epic and issues

```yaml
milestone:
  title: "v3.0 — Notifications"
  description: "Full notification system: preferences, delivery, history"

epic:
  title: "Notification Delivery"
  description: "Core notification sending infrastructure"

issues:
  - title: "Email notification sender"
    weight: 3
    description: |
      # Description
      Implement email delivery for triggered notifications.

      # Acceptance Criteria
      - Emails sent within 30s of trigger
      - Failed deliveries are retried up to 3 times
      - Delivery status logged
    milestone: "v3.0 — Notifications"
```
