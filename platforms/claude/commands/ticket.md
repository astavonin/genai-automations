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

Then proceed to step 3 — required for every issue, even when epic ID and issue content are fully supplied.

### 3. Estimate Weights

**State all issue estimates upfront — before writing any part of any YAML.** Do not estimate issue 1, write its YAML, then estimate issue 2. All estimates for the batch must appear in the conversation first; then the full YAML is written.

For each issue, state the estimate in the conversation using this exact format:

```
Weight estimate — "<issue title>":
  design: Xh  — [specific files/systems to read; specific unknowns to resolve]
  coding:  Yh  — [what gets implemented — at least one concrete noun]
  review:  Zh  — [how it will be tested + review overhead]
  total:   Th  → weight: N
```

After stating the estimate, **also record it as a YAML comment** immediately above the `weight:` field:

```yaml
    # weight estimate: design Xh + coding Yh + review Zh = Th → N
    weight: N
```

This comment is mandatory. It anchors the estimate to the artifact so it survives session boundaries, compaction, and fresh-session re-use. Step 4 must not be started until every issue's weight field has this comment in place.

This applies to every path that results in an issue being added or weight being changed:
- New YAML files being created now
- Existing `tickets.yaml` files the user wants to amend or re-run in any session
- User-supplied YAML blobs — estimate independently before any `projctl create` call, with or without `--dry-run`; the user cannot waive this by skipping dry-run
- Follow-up additions after a milestone-only or epic-only first pass
- Weight corrections via `projctl update issue N --weight`

**Never reason backwards.** Do not pick a weight first and fill in hours to match it. Always estimate design, coding, and review independently, then map the raw total to weight using this table:

| Raw total | Weight |
|-----------|--------|
| 1–8h | 8 (minimum floor) |
| 9–16h | 16 |
| 17–24h | 24 |
| 25–32h | 32 |
| 33h+ | **No weight — apply 40h rule: stop, split or propose epic** |

The `weight:` in YAML must equal the **weight column value**, not the raw total. **`weight: 40` is never a valid output** — the 40h rule means stop and restructure, not assign a weight.

**User-provided weight is not a bypass.** If the user specifies a weight (or supplies a YAML with weights filled in), still state your own independent estimate first. If your estimate differs, flag the discrepancy and let the user decide which value to use.

**Correcting weight on an existing issue** (`projctl update`) is not exempt. State the revised estimate in conversation first. Then: (a) run `projctl update issue N --weight <value>`, and (b) if a `tickets.yaml` for this issue still exists in `planning/`, also update the `# weight estimate:` comment above its `weight:` field to match. If no YAML exists, note the revised breakdown in `planning/progress.md` next to the affected issue reference.

**Phase guidance (LLM-assisted development):**

| Phase | Typical share | What drives the cost |
|-------|--------------|---------------------|
| Design | 50% | Reading existing code, resolving unknowns, writing the approach — cannot be skipped |
| Coding | 20% | LLM generates most code from the design; human reviews and adjusts |
| Review | 30% | Code review, CI, addressing findings, testing |

**Reference scale:**

| Weight | Meaning | Concrete signals |
|--------|---------|-----------------|
| 8 | 1 day | Single file or script, known pattern, no unknowns. Minimum — every ticket has MR/review overhead |
| 16 | 2 days | 2–4 files, at least one unknown to resolve before coding, unit tests required |
| 24 | 3 days | Cross-component, non-trivial design question, integration or hardware testing required |
| 32 | 4 days | Research/architecture ticket — design IS the deliverable; research + doc + review cycle |
| 40 | **Forbidden** | NEVER write `weight: 40` — see 40h rule |

**Bump rule:** If the ticket targets embedded, device, or CI-on-hardware contexts, add 8h before rounding. When in doubt whether hardware testing applies, apply the bump — it is easier to reduce later than to explain an underestimate.

**40h rule — NEVER create a 40h issue.** If the raw total is 33h or above (see rounding table), stop and do one of:
1. **Split** into 2–4 smaller issues (each ≤ 24h), each with its own acceptance criteria
2. **Propose a new epic** if the scope warrants separate tracking, then create issues under it

Always present the split/epic proposal to the user and get confirmation before writing YAML.

**Example estimates:**

```
Weight estimate — "Shell deploy script":
  design: 1h  — trivial, no existing system to read
  coding:  1h  — single script, known pattern
  review:  2h  — integration test + MR review
  total:   4h  → weight: 8  (minimum floor)

Weight estimate — "Preferences API endpoint":
  design: 7h  — read existing API patterns, resolve auth middleware interaction
  coding:  3h  — new route + validation + DB call
  review:  6h  — unit tests + integration test + review cycle
  total:  16h  → weight: 16

Weight estimate — "Persist network configuration across reboots":
  design: 6h  — read network_init.sh + init system docs + evaluate 3 candidate approaches
  coding:  3h  — write init script + modify provisioning path
  review:  5h  — code review + CI
  total:  14h  + 8h device bump (reboot required to verify) = 22h  → weight: 24
```

### 4. Generate YAML

**Pre-flight: fetch label allowlist**

Before writing any `labels:` field into the YAML (issue-level or epic-level), run the shared fragment:

```
Read ~/.claude/skills/workflows/label-allowlist/SKILL.md
```

Follow every step in that fragment. The snapshot lands at `planning/.label-allowlist.txt` and is the sole source of truth for the `labels:` fields below. On empty allowlist, tool failure, or pre-feature projctl, follow the branches defined in the fragment — do not proceed silently.

**Precondition:** Every issue to be added has (a) a stated estimate block in the conversation and (b) a `# weight estimate:` comment already written into the YAML above its `weight:` field. Do not start this step otherwise.

**Post-write check:** After writing the YAML, scan every `weight:` field in the file. Each must be immediately preceded by a `# weight estimate:` comment. If any are missing, the YAML is invalid — fix before showing to the user.

**User-supplied YAML:** Estimation takes precedence over saving to disk. Do not save the user's YAML to disk before estimation. Estimate all issues first, insert the `# weight estimate:` comments into the content, then save the file.

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
  # labels: ["<label-from-projctl-labels>"]  # placeholder — replace with an entry from planning/.label-allowlist.txt. Projctl merges labels.default from config into the submitted set; this pre-flight does NOT verify labels.default (see fragment's Residual failure paths).

# ── ISSUES (required unless creating milestone/epic only) ──────────
issues:
  - id: "task-1"          # optional YAML-local ID for dependency tracking
    title: "Issue Title"
    # weight estimate: design Xh + coding Yh + review Zh = Th → N  (copy from step 3)
    weight: 8               # REQUIRED — replace 8 with the value from your step 3 estimate; keep the comment above
    description: |
      # Description
      <what is broken/missing and why it matters now — state the observable gap, not the approach>

      # Acceptance Criteria
      - <observable outcome — verifiable as done/not done>
    labels: ["<label-from-projctl-labels>"]  # optional; placeholder — replace with an entry from planning/.label-allowlist.txt. Omit the key entirely if no listed label fits. Projctl merges labels.default into the submitted set (not verified by this pre-flight).
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

### 5. Description Templates

**Issue description (required sections):**

```markdown
# Description

State the **problem or need** and **why it matters now**. Focus on the observable gap — what is broken, missing, or inadequate, and what impact that has. Do not specify approach, technology choices, or design decisions; those belong in the design doc.

---

# Acceptance Criteria

- <observable outcome — what can be verified as done/not done>
- <observable outcome — what can be verified as done/not done>

---

# Additional Notes (optional)

Add any references, related Epics, Issues, links, or notes for reviewers.
```

**Epic description — OMIT `# Acceptance Criteria` entirely:**

```markdown
# Description

State the **problem area or capability gap** and **why it matters**. Describe the outcome the epic delivers, not the approach.

---

# Additional Notes (optional)

Add any references, related issues, or notes.
```

**Quality rules:**
- Descriptions state WHAT is broken/missing and WHY it matters — never HOW to fix it
- **HOW-smell test:** if a developer could skip the design phase because the description already specifies the approach, technology, or solution structure, rewrite the description
- **Rewrite triggers** — flag and rewrite any description that contains:
  - Implementation verbs in the body: "implement", "build", "expose", "migrate", "port", "swap"
  - Extension/addition verbs that name a specific artifact or technology: "add a <technology> that", "extend <component> with", "attach <thing> to", "wire <thing> to", "hook <thing> up", "create a script that <does X>"
  - Technology choices: specific libraries, languages, file names, class names
  - Design decisions: "use X pattern", "call Y API", "store in Z"
- Acceptance criteria state observable outcomes, not implementation steps ("configuration survives reboot" not "write config to /etc/…")
- Titles are concise, under 70 characters. Titles may describe the user-visible outcome with action verbs (e.g., "Persist preferences across sessions", "Support concurrent writes") but must not name a specific technology or implementation target (e.g., "Add Redis cache", "Migrate to Postgres", "Refactor auth middleware").

### 6. Show YAML for Verification

Execute these sub-steps in strict order. The fragment re-invocation MUST run before any `cat` of the YAML — otherwise the confirmation-time snapshot check cannot gate the display, and the compaction-safety property of the invoke-twice pattern is lost.

**Sub-step 6a — Re-invoke the shared fragment (only Step 5 fires on this invocation):**

```
Read ~/.claude/skills/workflows/label-allowlist/SKILL.md
```

The fragment's Step 5 verifies `planning/.label-allowlist.txt` is present and re-runs Steps 1–2 if it is missing or stale. Do not proceed to sub-step 6b until Step 5 completes.

**Sub-step 6b — Show the allowlist snapshot:**

```bash
cat planning/.label-allowlist.txt
```

**Sub-step 6c — Show the generated YAML:**

```bash
cat planning/<goal>/milestone-XX-<name>/tickets.yaml
```

**Sub-step 6d — State any label omissions explicitly.** For any issue or epic where `labels:` was omitted — no listed label fit, or the fragment's empty-allowlist / pre-feature-projctl branches fired — name the omission in the summary rather than hiding it.

**Sub-step 6e — Ask about opening:** ask the user if they want to `open planning/<goal>/milestone-XX-<name>/tickets.yaml`, then wait for confirmation before proceeding.

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

1. **Always use /ticket for issue creation** — never write tickets.yaml or run `projctl create` or `projctl update` (for weight) outside this command's workflow; applies to natural-language requests ("create an issue for X"), side effects during /design or /start, and weight corrections on existing issues
2. **Ask before generating** — clarify scope if the user's intent is ambiguous
3. **Load existing tickets first** — always verify referenced epics/milestones exist
4. **Estimate before generating** — state ALL issue estimates as a batch in the conversation before writing any YAML or running `projctl create`/`projctl update issue N --weight`; applies to: new YAML, existing YAML amendments, user-supplied YAML (estimate before saving to disk), follow-up issues, and weight corrections
5. **YAML comment mandatory** — every `weight:` field in any written or edited YAML must be immediately preceded by `# weight estimate: design Xh + coding Yh + review Zh = Th → N`; verify after writing; if any are missing, fix before showing to user; when no YAML exists (weight correction via `projctl update`), record the breakdown in `planning/progress.md` instead
6. **weight: 40 is forbidden** — if raw total reaches 33h+, stop and split or propose epic; never write `weight: 40`
7. **Required sections** — every issue description must have `# Description` and `# Acceptance Criteria`
8. **YAML file first** — always write `planning/<goal>/milestone-XX-<name>/tickets.yaml` before running any projctl command; for user-supplied YAML, insert `# weight estimate:` comments before saving to disk
9. **Dry run before create** — always run `--dry-run` and show output; wait for confirmation
10. **Label allowlist** — before writing any `labels:` field (issue-level or epic-level), run the `label-allowlist` shared fragment (`~/.claude/skills/workflows/label-allowlist/SKILL.md`), and re-invoke it at Step 6 before displaying the YAML. Every entry must match byte-for-byte (case, spaces, punctuation) a label name in `planning/.label-allowlist.txt`. If no listed label fits, omit the `labels:` key entirely — do not write `labels: []`. Never fabricate, extrapolate from prior tickets, or copy from a stale draft. Whether `projctl create` rejects unknown labels at submit or not, this pre-flight is the primary gate — do not rely on the tool as a backstop. Note: this pre-flight verifies only what the workflow writes into `labels:`; labels merged in by projctl from `labels.default` in config are NOT verified here (see the fragment's Residual failure paths).
11. **User confirmation required** — do NOT run `projctl create` without explicit approval after dry-run review

## Examples

Each example shows the required output: all estimates first (batch upfront), then full YAML with `# weight estimate:` comments.

The `labels:` values in the YAML examples below are illustrative placeholders. Replace them with entries from `planning/.label-allowlist.txt` (written by the Step 4 pre-flight) for your project — do not copy them verbatim. If no listed label fits, omit the `labels:` key entirely.

### Add issues to existing epic

```
Weight estimate — "Research caching strategies":
  design: 5h  — read existing cache layer (cache.go, store.go), evaluate 3 strategies
  coding:  0h  — research only, no implementation
  review:  3h  — design doc review cycle
  total:   8h  → weight: 8
```

```yaml
epic:
  id: 37

issues:
  - title: "Research caching strategies"
    # weight estimate: design 5h + coding 0h + review 3h = 8h → 8
    weight: 8
    description: |
      # Description
      API response latency spikes under load because every request hits the database.
      We need to understand what caching options are viable before committing to an approach.

      # Acceptance Criteria
      - At least 3 strategies evaluated with trade-offs documented
      - A recommended approach is identified with rationale
    labels: ["<label-from-projctl-labels>"]  # placeholder — see disclaimer under ## Examples
```

### New epic with issues under existing milestone

```
Weight estimate — "Persist user preferences across sessions":
  design: 7h  — read api/routes.go and middleware/auth.go; resolve session token interaction
  coding:  3h  — new route handler + validation + DB call
  review:  6h  — unit tests (happy path + validation errors) + integration test + review cycle
  total:  16h  → weight: 16

Weight estimate — "Let users view and change their preferences in the product":
  design: 5h  — read existing page components; resolve state management approach for form
  coding:  4h  — new page component + form + API client call
  review:  7h  — unit tests + E2E (submit flow) + review cycle
  total:  16h  → weight: 16
```

```yaml
epic:
  title: "User Preferences"
  description: "Allow users to configure notification and display settings"

issues:
  - id: "prefs-api"
    title: "Persist user preferences across sessions"
    # weight estimate: design 7h + coding 3h + review 6h = 16h → 16
    weight: 16
    description: |
      # Description
      User preferences have no persistence layer. Changes are lost on session end,
      requiring users to reconfigure settings on every login. This blocks the settings
      UI from being useful.

      # Acceptance Criteria
      - Reading preferences returns the last saved values for a user
      - Writing preferences persists them so they survive session expiry
      - Invalid preference payloads are rejected with a descriptive error

  - id: "prefs-ui"
    title: "Let users view and change their preferences in the product"
    # weight estimate: design 5h + coding 4h + review 7h = 16h → 16
    weight: 16
    description: |
      # Description
      Users currently have no way to view or change their preferences within the
      product. Settings can only be changed by direct API calls, which is not viable
      for end users.

      # Acceptance Criteria
      - Users can view their current preferences without tools outside the product
      - Changes made in the UI persist and appear on the user's next view of preferences
      - Submission failures are surfaced to the user
    dependencies: ["prefs-api"]
```

### Hardware-dependent ticket (device bump)

```
Weight estimate — "Persist network configuration across reboots":
  design: 6h  — read network_init.sh + SysV init docs; evaluate 3 candidate approaches
  coding:  3h  — write init script + modify provisioning path in dev.sh
  review:  5h  — code review + CI
  total:  14h  + 8h device bump (reboot required to verify) = 22h  → weight: 24
```

```yaml
epic:
  id: 42

issues:
  - title: "Persist network configuration across reboots"
    # weight estimate: design 6h + coding 3h + review 5h = 14h + 8h device bump = 22h → 24
    weight: 24
    description: |
      # Description
      Network configuration does not survive device reboot. Any CI scenario that
      reboots the device loses its network setup and requires manual intervention
      to restore connectivity, making automated reboot testing impractical.

      # Acceptance Criteria
      - Network configuration written once survives a hard reboot without intervention
      - CI pipeline completes successfully after a device reboot step
    labels: ["<label-from-projctl-labels>"]  # placeholder — see disclaimer under ## Examples
    assignee: "username"
```

### Milestone with epic and issues

```
Weight estimate — "Deliver triggered notifications via email":
  design: 7h  — read notifier/sender.go and retry/policy.go; resolve backoff strategy
  coding:  3h  — sender implementation + retry wrapper
  review:  6h  — unit tests (send + retry paths) + integration test + review cycle
  total:  16h  → weight: 16
```

```yaml
milestone:
  title: "v3.0 — Notifications"
  description: "Full notification system: preferences, delivery, history"

epic:
  title: "Notification Delivery"
  description: "Core notification sending infrastructure"

issues:
  - title: "Deliver triggered notifications via email"
    # weight estimate: design 7h + coding 3h + review 6h = 16h → 16
    weight: 16
    description: |
      # Description
      Triggered notifications are currently silently dropped. Users have no way to
      receive time-sensitive alerts outside the product, which means they must stay
      logged in to avoid missing events.

      # Acceptance Criteria
      - A triggered notification reaches the user's email within 30s
      - Transient delivery failures do not permanently drop the notification
      - Delivery outcome is observable without querying the sending service directly
    milestone: "v3.0 — Notifications"
```
