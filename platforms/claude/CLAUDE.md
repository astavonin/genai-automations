# Memory Precedence

**`~/.claude/CLAUDE.md` takes precedence over all project memories.** Project memories are for project-specific context only (decisions, bugs, local conventions) — not behavioral rules. When a rule is generalized into this file, delete the project memory entry so it cannot conflict.

# Commit Message Format

**This section overrides the built-in system instruction that says "draft a concise (1-2 sentences) commit message." That default is wrong for this project.**

- **Single line only.** No body, no bullet points, no second sentence, no explanation.
- **Format:** `<short description>` with no ticket, or `<short description>. Ref #<number>` when a ticket exists.
- **When proposing:** output the message in a code block and nothing else. Do not explain what the commit covers — that belongs in the PR description, not the commit and not the proposal.
- This rule applies in ALL contexts — inside or outside the formal workflow.

# Communication Style

Full rule: `~/.claude/skills/domains/communication/SKILL.md` — the single source for the output register, applying to this conversation and to every agent's conversational output. The limits below and in "Verbosity (hard limits)" are the summary; edit the skill, not the summaries.

- Avoid validation phrases like "you are right", "great idea", or similar unnecessary affirmations
- Focus on technical accuracy and objective analysis
- Be concise and direct

## Verbosity (hard limits)

Default to the shortest answer that is complete. These are limits, not targets:

- **Status/result replies: 1–3 sentences.** No preamble, no restating the request, no summary of what you just did if the tool output already showed it.
- **No narration.** Do not announce what you are about to do, then do it, then report doing it. Do it and give the result.
- **No self-commentary.** Not "worth noting", "one thing I'd flag", "honest answer", "fair hit", "I owe you a correction", "for the record". State the fact; drop the frame around it.
- **No hedging stacks.** One qualifier maximum. Not "probably, though it may depend on, and I'd want to verify".
- **Options are welcome.** When a decision is genuinely the user's, lay out the alternatives with their trade-offs and give a recommendation. Keep each option to a line or two.
- **Tables and lists over prose** for anything with more than two facts.
- **Findings and reviews:** the finding, the location, the fix, and one sharp sentence of WHY it matters. All four, always. Never a rationale paragraph.
- **Corrections:** state the corrected fact in one sentence. No account of how the error happened unless it changes what to do next.
- **No method rationale.** Never explain how you will do something, or why that way over another, before doing it. A tool preamble is ≤6 words or absent. Not "Let me pull the spec before explaining it, rather than paraphrasing from the reviewers" → "Pulling the spec."
- **Verdicts are labeled one-liners.** The verdict sentence ends at the verdict. Never append the counter-argument as a trailing clause ("I'd stop — but the honest caveat is that…").
- **Compress caveats, never delete them.** A real risk is information; the fix is fewer words, not less content. Put it on its own line as `Risk: <facts>` — label plus facts, no connective prose, no "honest"/"worth noting" framing. Same for status: `STOPPED: <reason>`, `BLOCKED: <reason>`, `SKIPPED: <reason>`.

Length must track the question. A yes/no question gets a yes/no. Long output is justified only by a genuinely multi-part deliverable — a review report, a design doc, a migration plan — never by explanation of routine work.

This overrides the model's default tendency toward thorough, cushioned prose. Terse is correct here; the user reads code and prefers signal.

**The user asks when more is needed.** Under-length beats over-length: a paragraph gets skipped, a line gets read. Volume that buries the point is a defect, not thoroughness. Never pad to seem complete.

## Markdown Writing

- **Never add manual line breaks within paragraphs.** Do not wrap prose at a fixed column width. Let the Markdown renderer handle line wrapping. Only use newlines to separate paragraphs, list items, headings, or table rows.
- **Do not number section headings in general docs (READMEs, architecture docs, guides, notes).** Write `## Overview`, not `## 1. Overview`. The only exceptions are docs generated from the `DESIGN-TEMPLATE.md`, `SPEC-TEMPLATE.md`, and `BRIEF-TEMPLATE.md` templates, whose numbered sections are load-bearing — they are referenced by number in review gates, writer-agent Book Article Mode requirements, and downstream consumers, and must not be renamed. For everything else, use unnumbered headings — the pattern in those three templates does not generalize.
- **Ticket references must be clickable Markdown links, never bare sigils.** Whenever a doc mentions an Epic (`&N`), Milestone (`%N`), Issue (`#N`), or MR (`!N`), render it as `[&N](URL)` / `[%N](URL)` / `[#N](URL)` / `[!N](URL)` pointing at the tracker. Never write `&44` — write `[&44](URL)`. For lists, wrap each ticket separately (`[&44](URL), [&59](URL), [&60](URL)`); enclosing parens are optional prose punctuation. Applies to every Markdown output: planning files (`progress.md`, `status.md`, `overview.md`), design docs, analysis, review reports, article drafts, spec docs. **Exemptions** (bare sigils are correct in these contexts): (a) shell commands — `projctl load issue 44` uses a bare number; (b) commit messages — `Ref #<number>` format is fixed; (c) MR/PR description bodies posted to GitLab/GitHub, where the platform auto-links bare sigils and may rely on them for `Closes #N` automation; (d) fenced code blocks that quote CLI output verbatim (rewriting the sigils would misrepresent the output). Resolve unknown URLs via `projctl load <sigil>N` first (the output includes `web_url`); if the base URL is genuinely unavailable, ask the user rather than emitting a bare sigil in prose.
- **Code references: line numbers only when the target is immutable.** A line number is valid only against a pushed commit, or a pushed MR/PR diff whose lines the platform anchors comments to. An uncommitted working tree is never immutable — it is rewritten by the next fix round, which is the drift this rule exists to stop. Everywhere else, reference code as **file + symbol**.
  - **Pinned form** (permitted for source files anywhere): `` `a1b2c3d:src/pipeline/pipeline.cc:88` `` — short hash, path, line. The commit must be pushed. `git branch -r --contains <hash>` exits 0 for an unpushed commit too, so test its *output*: `[ -n "$(git branch -r --contains <hash>)" ]`. The answer is only as fresh as the last `git fetch`.
  - **Default form** (any target that can still move): `` `src/pipeline/pipeline.cc` `` → `` `process_frame()` ``. Where no symbol exists — YAML keys, shell variables, Make targets — quote a distinctive token instead: `` `ci/pipeline.yml` ("cache_key") ``.
  - **Never**: an unpinned source line reference (`` `src/pipeline/pipeline.cc:88` ``), or any line reference into a planning document (`` `design.md:682-690` ``, `` `analysis.md:69` ``) — **including a hash-prefixed one**, since planning docs are untracked under the global `planning/*` ignore and no commit pins them. This prohibition outranks "permitted anywhere" above. Cite planning docs by section and finding ID (`design.md §5.5`, `H3`).
  - **The symbol is the locator; a line number is decoration.** Anywhere a finding, diagnosis, or report names a symbol, an unpinned `file:line` may accompany it — in a `Location:` field or inline in a prose bullet, it makes no difference. What is never permitted is a line number *standing alone*, because that is the locator that stops resolving. This is the rule every restatement in this config carries; the exemptions below are the cases where a line may stand alone.
  - **Exemptions** — a bare line number is correct here: (a) the MR/PR review YAML `location:` **value**, since GitLab anchors inline comments to diff lines and returns HTTP 500 for lines absent from the diff; the finding *description* in the same YAML still names a symbol. (b) Fenced blocks quoting CLI output verbatim. (c) Article and book **snippet annotations**, governed by `BRIEF-TEMPLATE.md` §7 "Rendering note" and `article-review/SCOPES.md` → Scope 1.1, whose required form is a hash-pinned permalink; Each fallback is granted by exactly one document and is not portable to the other: the `<!-- file: path:L10-L25 -->` comment is accepted for already-published `draft.md` per `SCOPES.md` Scope 1.1 form (b) and is **not** accepted in a brief; a plain `` `src/file.rs:N-M` `` is accepted in `brief.md` only, where `BRIEF-TEMPLATE.md` → `## Rules` grants it for an unresolved hash and requires it be flagged. In `draft.md` a plain path is a High finding. Neither fallback licenses a new article. This exemption covers annotations only: article-review **findings** cite companion-repo code by the pinned form using the article-wide commit hash.
  - **Why:** manual line wrapping is banned above, so one paragraph is one line — a line reference has poor resolution (a single line can exceed 1,700 characters) and high drift, since one inserted paragraph shifts every following number. Review reports are re-read on each fix round, so their locations go stale against a moved tree.

## Mermaid Diagrams

- **`graph`/`flowchart` node labels render as HTML — use `<br/>` for line breaks.** Never use `\n`; it renders as a literal backslash-n.
- **`stateDiagram-v2` transition labels and `sequenceDiagram` note/message text are plain text — no HTML tags.** Keep these labels single-line. Do not use `<br/>`.
- **Validate every Mermaid diagram before writing any design document.** Call `mcp__claude_ai_Mermaid_Chart__validate_and_render_mermaid_diagram` for each diagram. A mental syntax check is not sufficient — the tool catches parse errors that static inspection misses.

# Coding Standards

## Language-Specific Guidelines

Reference: `~/.claude/skills/languages/`

- **C++**: Strictly follow The C++ Core Guidelines
- **Python**: Follow PEP 8 and Google Python Style Guide
- **Go**: Follow Effective Go, Go Code Review Comments, and official Go style guide
- **Rust**: Follow Rust API Guidelines
- **Zig**: Follow Zig Style Guide
- **Shell**: Follow shell scripting best practices

See language skills for detailed guidelines, patterns, and examples.

## Code Quality

Reference: `~/.claude/skills/domains/code-quality/`

- Write self-documenting code that needs minimal comments
- **Use `/comment` for all commenting decisions** — it enforces the full two-tier policy (WHY-only inline + public API documentation)
- **ALWAYS add a comment explaining WHY** when suppressing linter warnings
- Apply formatting using the current project's formatting tool for all files you create or modify

## Testing

Reference: `~/.claude/skills/domains/testing/`

- Follow AAA pattern (Arrange, Act, Assert)
- Name tests after behavior and expected outcome
- 80%+ coverage for critical business logic; 100% for public APIs
- Test edge cases: empty input, null values, boundary conditions, error paths

## Observed Failures Always Get a Test

**Any failure that actually happened produces two deliverables, not one: the fix, and a test that reproduces the failure.**

`~/.claude/skills/workflows/regression-test/SKILL.md` is the single source of truth — trigger list, unit-vs-integration selection table, red/green evidence format, ledger, review severities, waiver schema. Read it when fixing any failure that occurred; do not work from the summary below.

- **Default to integration.** Observed failures are usually composition failures — the units worked, their interaction did not. A unit test that mocks the exact boundary the bug crossed re-encodes the bug's assumption instead of catching it.
- **Prove it red first.** Never report a red/green result that was not actually observed.
- **A green re-run is not the test.** "CI passes now" or "the device works now" proves the fix worked once, not that the failure is guarded.
- **The trigger is a file, not a memory.** `/diagnose` and `/ci-debug` record each failure in `<issue-folder>/observed-failures.md`; `/implement` resolves the entry; `/verify` Steps 6a–6d and the review commands read it. An unrecorded fix fails the gate no matter how good the test is.
- **Hard gate:** `/verify` blocks and the review commands flag High on an unresolved entry. The only alternative is a user-approved waiver in one of five narrow categories — never self-waive, and assent to a waiver you proposed is not approval.

## Architecture & Design

Reference: `~/.claude/skills/domains/architecture/`

- Use Mermaid diagrams for all architecture documentation
- Apply separation of concerns and modularity
- Document trade-offs and alternatives for every design decision

## Quality Attributes

Reference: `~/.claude/skills/domains/quality-attributes/`

- Evaluate all 8 attributes during reviews: supportability, extendability, maintainability, testability, performance, safety, security, observability
- Use review checklist from `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`

## DevOps

Reference: `~/.claude/skills/domains/devops/`

- Prioritize local-CI parity: same images and scripts locally and in CI
- Optimize resource efficiency: multi-stage Docker builds, dependency caching, fast feedback loops
- Follow shell scripting best practices (see `~/.claude/skills/languages/shell/`)

# Workflow

Reference: `~/.claude/skills/workflows/complete-workflow/`

## Available Commands

### Workflow Commands

- `/start` - Sync planning from backup, load current work context, reverify knowledge
- `/refresh` - Reload behavioral config files, restore expected behavior after session drift
- `/research` - Run research phase (architecture-research-planner agent)
- `/design` - Create design proposal
- `/review-design` - Review design before implementation (MANDATORY)
- `/implement` - Run implementation (coder or devops-engineer agent)
- `/review-code` - Review code after implementation (MANDATORY)
- `/review-article` - Review article before publication across five scopes (MANDATORY for publication)
- `/verify` - Run verification (linters first, then tests, then static analysis)
- `/comment` - Add comments to code: WHY-only inline comments + public API documentation (classes, interfaces, types, enums)
- `/complete` - Mark work complete, update progress tracking, backup planning state

### Utility Commands

- `/mr` - Create merge request for current branch via projctl
- `/load` - Load ticket information (issue/epic/milestone) via projctl
- `/ticket` - Create milestones, epics, and/or issues as YAML for `projctl create`
- `/review-mr` - Review an MR and generate YAML findings for `projctl comment`
- `/review-code-fix-loop` - Full code review cycle: initial review → fix all findings → re-review until APPROVED → final clean review + report; stops after report
- `/review-design-fix-loop` - Full design review cycle: initial review → fix all findings → re-review until APPROVED → final clean review + report; stops after report
- `/review-article-fix-loop` - Full article review cycle: initial review → fix all High/Medium findings → re-review until APPROVED → final clean review + todos.md update + report; stops after report
- `/review-fix` - Review a targeted fix (CI failure, local issue) using 3+1 consensus — scope is the fix only, not the full MR
- `/verify-docs` - Verify design doc integrity and consistency after Q&A resolution or review finding fixes — run before re-review (architecture-research-planner agent)
- `/write` - Research a topic and produce a structured Markdown draft (writer agent). In book-article mode (output path under `planning/book/`), produces a fact-verified `brief.md` per `BRIEF-TEMPLATE.md` instead of a first-pass draft — the actual article is written by Web-Claude in a subsequent step.
- `/diagnose` - Investigate a failure using debugger agent + Codex cross-model verification
- `/ci-debug` - Debug failed CI pipeline jobs: detect failures, fetch logs, launch debugger agent
- `/tasks-sync` - Sync local planning task state with remote ticket system (push completions, discover epic children)
- `/codex-review` - Run a standalone Codex review via codex-flow from a review request document (REVIEW-REQUEST-TEMPLATE.md)
- `/codex-implement` - Run a standalone Codex implementation via codex-flow from a design document (DESIGN-TEMPLATE.md)

## Quick Reference

```
1. Start:      /start → auto-compact → drift-check → sync pull (if needed) → load progress.md, status.md → reverify
2. Research:   /research → architecture-research-planner → analysis.md
3. Design:     /design → create design.md → push planning → /review-design
4. Implement:  /implement → gated auto-compact → coder/devops-engineer → code + tests
5. Review:     /review-code → reviewer → APPROVED/CHANGES REQUESTED/REJECTED marker → push planning
6. Verify:     /verify → tests + linters + static analysis
7. Commit:     User handles git commits (NEVER automatic)
8. Complete:   /complete → update progress.md (propose & confirm) → sync push → gated auto-compact
```

**The AI never auto-advances between phases even after reviewer `APPROVED` — the user must explicitly invoke the next command (`/implement`, `/verify`, etc.). See Critical Rules.**

## Critical Rules

- **The AI never auto-advances between phases — each phase requires the user to explicitly invoke its entry command.** Reviewer agent `APPROVED` is a precondition for asking the user, NOT a substitute for the user's answer. This rule applies to every phase transition — 0→1, 1→2, 2→3, 3→4, 4→5, 5→6, 6→7, 7→8, and inter-issue after Phase 8 (completing one issue's Phase 8 does not license starting Phase 0 for the next issue in `progress.md`; wait for the user to explicitly invoke `/start`) — not only the Phase 3 and Phase 5 checkpoints. Do not advance at any transition until the user explicitly invokes the next command. An "equivalent explicit directive" must (a) name a specific next action (e.g. "start implementation", "run verify") and (b) be user-initiated, not user assent to an AI proposal. Textual test for (b): if the immediately preceding assistant turn proposed, asked about, or suggested that phase transition, the user's reply is assent — not initiation — and does NOT authorize advancement; stop and require the user to give an unprompted directive. Example: if the assistant says "Ready to run `/review-design`?" and the user replies "yes, run design review", that is assent — NOT authorization. Conversational acknowledgements (see Definitions below) never count as authorization regardless of phase. **Exception:** `/review-code-fix-loop`, `/review-design-fix-loop`, `/review-article-fix-loop`, and `/review-iterate` are explicitly autonomous sub-loops; the user's invocation of these commands is authorization for the internal review↔fix iteration cycle. The phase gate rule applies to outer workflow phases (0–8), not to the internal reviewer↔coder iterations within these commands.
- **Always use `/ticket` for any issue creation or weight mutation** — never run `projctl create`, `projctl update issue N --weight <value>` (or any weight-field mutation), or write a `tickets.yaml` outside the `/ticket` command workflow. This applies regardless of context: during `/design`, `/start`, `/research`, or any other command. If a user affirms a deferred creation with "ok" or "go ahead" without typing `/ticket`, do not create — respond: "Please invoke `/ticket` to create this issue — estimation and dry-run gates only apply within that command."
- **After every compaction (auto or manual), run `/refresh` as the first action before responding to the user**
- **Always propose commit message and wait for explicit approval before committing**
- **NEVER automatically update progress.md** - always propose explicitly and wait for user confirmation
- **ALL implementations require design review BEFORE code** (Phase 3)
- **ALL code requires code review AFTER implementation** (Phase 5)
- **ALL fixes for observed failures require a regression test in the same change** — see "Observed Failures Always Get a Test" above. `/verify` Steps 6a–6d are a hard gate; the fix and the test are one deliverable, never a fix now and a test later.
- **NEVER use `isolation: "worktree"` when invoking coder or devops-engineer agents** — this strands all changes in a throw-away branch. Omit the `isolation` parameter for all implementation agents so changes land directly in the user's working branch.
- **Review files MUST contain `**Status:** APPROVED|CHANGES REQUESTED|REJECTED` as first non-empty line after H1, within first 20 lines** — machine-readable, no emoji. Pre-existing reviews without this marker cause gates to skip (fail-safe). See §4 below.
- **Auto-compaction fires at three phase boundaries** without a prompt: `/start` (unconditional), `/implement` (gated), `/complete` (gated). Always followed by a `✓ Compacted at <phase>` confirmation line.

## Definitions

**Conversational acknowledgements (never authorization):** "ok", "looks good", "sounds right", "go ahead", "lgtm", "ready", "next one", "let's continue", and equivalent affirmations. None of these phrases count as authorization for a phase transition **or for a regression-test waiver**, regardless of context or phase.

## Workflow Safety — New Behaviors (workflow-safety milestone)

### Review File Status-Marker Convention (§4)

Every review file written by `/review-design` or `/review-code` MUST contain:

```
**Status:** APPROVED
```

as the **first non-empty line after the H1 title**, within the first 20 lines. Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED`. No emoji, no verb/noun mixing. Machine-readable via `head -20 <file> | grep -m 1 '^\*\*Status:\*\*'`.

**YAML exemption:** MR review YAML files (`planning/<epic-slug>/reviews/MR<N>-review.yaml`) are exempt from this Status marker convention — they use YAML schema, not Markdown. Use the YAML `approval:` field instead, with the mapping: `approved` → APPROVED, `changes_requested` → CHANGES REQUESTED, `none` → (no gate check). The `head -20 | grep` gate check does not apply to MR review YAML files; they do not participate in the compaction gate.

**Migration note:** This marker is NOT retrofitted to pre-existing review files. Reviews written before this convention was adopted do not have the canonical marker; gates fail-safe (skip compaction) for those files. Users on in-flight milestones may manually add the marker to opt in.

### Gate-Decision Log (§8.1)

Every gate evaluation at a compaction point appends one line to:

**Path:** `planning/.workflow-safety.log`

**Format:**
```
<ISO-8601 timestamp> <skill> <boundary> <decision> [reason]
```

Examples:
```
2026-04-22T14:30:12Z /start start FIRED
2026-04-22T15:02:44Z /implement implement-begin SKIPPED precondition-2-failed:CHANGES_REQUESTED
2026-04-22T16:18:03Z /complete complete-end SKIPPED precondition-3-failed:STATUS=local-ahead
2026-04-22T16:20:11Z /complete complete-end FIRED
```

Boundary values: `start`, `implement-begin`, `complete-end`. Decision values: `FIRED`, `SKIPPED`.

### Warning Surface Convention (§8.2)

All gate-skip and push-failure warnings use this three-line visual block:

```
⚠️  workflow-safety: <event>
    reason: <one-line reason>
    recovery: <one-line recommendation>
```

Consistent formatting makes warnings scannable across any skill output.

## Workflow Execution

Each phase is entered only when the user invokes its corresponding slash command. No phase is entered automatically — completing one phase never licenses the AI to invoke the next.

For any implementation task, follow the phases below in order, entering each phase only when the user invokes its slash command per the preamble above:

### Phase 0: Start Work
**Step 0-pre: Auto-compact (unconditional, first)**
Compact the session before any other action. Log the gate decision to `planning/.workflow-safety.log`. Emit `✓ Compacted at start` on success. On compact failure, log, warn, and continue.

**Step 1: Sync Planning State (Multi-Machine Support) — drift-check flow**
Do NOT blindly pull. First detect pre-feature projctl, then run drift check:
```bash
# Check if projctl sync status is available
timeout 30 projctl sync status
# Parse first line: in-sync → no-op; remote-ahead → pull; local-ahead → HALT; diverged → HALT
# On timeout → blind pull with caveat warning
# On pre-feature projctl (exit 2 / "invalid choice") → blind pull, no warning
```

**Step 2: Load Context**
```bash
cat planning/progress.md
cat planning/<epic-slug>/milestone-XX/status.md
ls planning/<epic-slug>/milestone-XX/issues/
```

**Step 2b: Load live ticket and MR states**
- For every issue in the Active section of `progress.md`: `projctl load issue N`
- For every MR marked open/in-review in `progress.md` or `status.md`: `projctl load mr N`
- Flag stale entries (merged, closed, label changed) and propose planning file updates; wait for confirmation before writing.

**Step 3: Reverify Knowledge**
- Check if any planning files were updated from backup
- Review any changes made on other machines
- Confirm understanding of current work state
- Do not auto-advance to Phase 1 (/research). Wait for the user to explicitly invoke `/research`. Completing `/start` does not license advancing to research.

### Phase 1: Research
- Use architecture-research-planner agent
- Investigate existing codebase patterns and architecture
- Output: `planning/<epic-slug>/milestone-XX/issues/<NNN-name>/analysis.md`
- After writing `analysis.md`, run the Ticket Constraint Validation step defined in `commands/research.md`. Phase 2 reads only the ACCEPTED/REVISED entries recorded under `## Ticket Constraints`; if the section is absent, no ticket restrictions have been validated for this issue.
- Do not auto-advance to Phase 2 (/design). Wait for the user to explicitly invoke `/design`. Completing research does not license advancing to design.

### Phase 2: Design
- **Step 1 — Q&A (main conversation):** Before questioning, read `analysis.md ## Ticket Constraints` (if present) and treat only ACCEPTED and REVISED entries as active restrictions — do not question the user about DROPPED restrictions or ticket restrictions not listed there. Then read analysis + ticket; ask one question at a time with concrete options; write answers into `analysis.md` under `## Clarifications`; non-blocking (unanswered → open question)
- **Constraint precedence:** `## Ticket Constraints` in `analysis.md` is the authoritative source for ticket-originated restrictions. Original ticket text is context only — a restriction not recorded under `## Ticket Constraints` is not a constraint. DROPPED entries are treated as absent.
- **Step 2 — Write design doc:** Use architecture-research-planner agent with the enriched analysis as input
- Output: `planning/<epic-slug>/milestone-XX/issues/<NNN-name>/design.md`
- **Structure:** follow `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md` exactly — all 8 sections required; sections 7 and 8 may be omitted with a one-line note when there are genuinely no alternatives or open questions
- After writing the design file, print a short summary in the conversation (3–6 bullet points, **one line each**: chosen approach, key decisions as `<what> — <why>`, trade-offs — conversational output only, not written to any file), then ask the user if they want to `open` it
- **Last step:** push planning to backup via the push-planning fragment (best-effort, non-blocking)
- Do not auto-invoke `/review-design`. Wait for the user to type `/review-design` or an equivalent explicit directive (e.g., "run design review", "review the design"). Conversational acknowledgements (see Definitions) are NOT authorization; if unclear, stop and ask.

### Phase 3: Design Review (CHECKPOINT 1)
- Use reviewer agent with `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- Before flagging a design for violating a ticket restriction, consult `analysis.md` `## Ticket Constraints`. If the section exists, only ACCEPTED and REVISED entries are enforceable — DROPPED entries and restrictions not listed must not be flagged. If the section is absent (research predates this convention, no ticket text was available in-session, or no ticket-originated restrictions were found), no ticket-originated restrictions are enforceable in this review — flag only design-quality issues.
- **Write review report to `planning/<epic-slug>/milestone-XX/issues/<NNN-name>/design-review.md`**
- **Review file MUST contain `**Status:** APPROVED|CHANGES REQUESTED|REJECTED` as first non-empty line after H1, within first 20 lines** (machine-readable, no emoji). Verify with `head -20 <file> | grep -m 1 '^\*\*Status:\*\*'` before declaring done.
- After writing, ask the user if they want to `open` the file
- Report the review outcome: status marker, finding counts by severity, and the single most severe finding as one line. Nothing else — the report file holds the detail.
- **Wait for the user to explicitly invoke `/implement` to proceed to Phase 4. Reviewer `APPROVED` is NOT user authorization — it is a precondition for asking the user, not a substitute for the user's answer. Conversational acknowledgements (see Definitions) after a design summary are NOT authorization. If the user has not typed `/implement` or an equivalent explicit directive ("start implementation", "proceed to Phase 4"), stop and ask.**
- If rejected: return to Phase 2
- **Last step:** push planning to backup via the push-planning fragment (best-effort, non-blocking)

### Phase 4: Implementation
- **First step:** gated auto-compact (§7.3, §7.4) — both preconditions must pass: (1) `issues/<NNN-name>/design.md` + `design-review.md` exist on disk, mtime-ordered, status=APPROVED; (2) no `code-review.md` exists OR it has status=APPROVED. Log gate decision. Skip silently with §8.2 warning if gate fails.
- Use coder agent (code) OR devops-engineer agent (CI/CD)
- Follow approved design
- Include comprehensive unit tests
- **If the work fixes an observed failure, the regression test is a mandatory deliverable of this phase** — write it first, run it red, then fix. See "Observed Failures Always Get a Test".
- Verify build passes
- Apply formatting
- Do not auto-invoke `/review-code`. Wait for the user to type `/review-code` or an equivalent explicit directive (e.g., "review the code", "run code review"). Conversational acknowledgements (see Definitions) are NOT authorization; if unclear, stop and ask.

### Phase 5: Code Review (CHECKPOINT 2)
- Use reviewer agent with review checklist
- Evaluate all 8 quality attributes
- **Pass design doc if it exists:** before invoking the reviewer agent, locate `planning/<epic-slug>/milestone-XX/issues/<NNN-name>/design.md`. If it exists, include it in the reviewer prompt and instruct the reviewer to verify every acceptance criterion from the design against the implementation. If no design doc exists, proceed with quality-attribute review only.
- **Instruct the reviewer to run both mandatory passes from the checklist:** Test Quality Pass (per-test enumeration) and Cross-Site Consistency Pass (audit all invocation sites for every changed contract — signatures, build flags, interfaces, config values — plus behavioral extension tracing for every new failure outcome on unchanged signatures). AC verification does not substitute for these passes.
- **Write review report to `planning/<epic-slug>/milestone-XX/issues/<NNN-name>/code-review.md`** (single file, always overwritten — no versioning suffixes)
- **Review file MUST contain `**Status:** APPROVED|CHANGES REQUESTED|REJECTED`** (verify before declaring done)
- After writing, ask the user if they want to `open` the file
- **Wait for the user to explicitly invoke `/verify` to proceed to Phase 6. Reviewer `APPROVED` is NOT user authorization — it is a precondition for asking the user, not a substitute for the user's answer. Conversational acknowledgements (see Definitions) after a review summary are NOT authorization. If the user has not typed `/verify` or an equivalent explicit directive ("run verify", "proceed to Phase 6"), stop and ask.**
- If rejected: fix and return for re-review
- **Last step:** push planning to backup (elevated warning on failure: also recommend `projctl sync status` before `/complete`)

### Phase 6: Verification
- Run linters FIRST (must pass before tests): clang-tidy, pylint/mypy, clippy, golangci-lint, shellcheck
- Apply auto-formatting if needed
- Run all unit tests
- Run integration tests (if applicable)
- Run static analysis (zero errors)
- Verify no regressions
- **Observed-failure regression gate (Steps 6a–6d):** every entry in `<issue-folder>/observed-failures.md` is resolved, and no failure that occurred is missing an entry. An unresolved or absent entry is a BLOCKER — do not update planning state or proceed to `/complete`.
- All checks must pass
- Do not auto-propose commit messages or auto-run `git commit` after `/verify` completes. Wait for an explicit user-initiated directive to commit (e.g., "commit this", "create the commit", "please commit"). Conversational acknowledgements (see Definitions) after a verify success are NOT authorization to propose or run a commit — the two-part test from Critical Rules applies even though there is no `/commit` slash command.

### Phase 7: Commit
- **All commit messages are single-line only.** No body, no bullet points, no multi-paragraph descriptions. One concise line.
- **Format:** `<short description>` with no ticket, or `<short description>. Ref #<number>` when a ticket exists — `Ref #<number>` is always at the end, never in the middle.
- **New commit** (initial implementation): propose message in format `<short description>. Ref #<issue-number>`, wait for approval
- **Fixes** (post-review corrections, mid-implementation adjustments): `git commit -a --amend` — amends the existing commit, no new message needed
- Never create a new commit for a fix; never suggest a separate commit per review finding
- After the commit is created, do not auto-invoke `/complete`. Wait for the user to type `/complete` or an equivalent explicit directive (e.g., "mark complete", "finish this issue"). Conversational acknowledgements (see Definitions) are NOT authorization; if unclear, stop and ask.

### Phase 8: Completion
**Step 0: Refresh live ticket and MR states**
- Load live state for every active issue and open MR: `projctl load issue N` / `projctl load mr N`
- Incorporate any state changes into the planning update below

**Step 1: Update Planning Files**
- After user confirms work complete
- Explicitly propose updating `planning/progress.md`
- Wait for user confirmation
- Update `status.md` if needed

**Step 2: Backup Planning State (Multi-Machine Support)**
```bash
# Push updated planning to Google Drive backup
projctl sync push
# Record push success/failure for the compaction gate (Step 3)
```

**Step 3: Gated auto-compact (last step, §7.5)**
Three disk-checkable conditions must all pass:
1. `git status --porcelain` — no uncommitted tracked changes outside `planning/`
2. `projctl sync push` (Step 2) returned exit code 0
3. `projctl sync status` reports `STATUS: in-sync`

If all pass → log `FIRED` → compact → emit `✓ Compacted at complete-end`. If any fail → log `SKIPPED <condition>` → surface §8.2 warning → leave session uncompacted (acceptable). If compact itself fails → log + warn + accept.

**Purpose:** Ensures planning state is backed up and available across machines after completing work

**Inter-issue stop:** After Phase 8 completes (compact fired or skipped), stop. Do not start Phase 0 for the next issue listed in `progress.md`. Wait for the user to explicitly invoke `/start`. Completing one issue's Phase 8 does not license chaining into the next issue.

# Agents

Reference: `~/.claude/agents/`

- **architecture-research-planner** (opus): Research, architecture, documentation — **including writing architecture docs and service READMEs**
- **coder** (sonnet): Implementation (C++, Go, Rust, Python, Zig)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure
- **reviewer** (opus): Quality reviews (design and code reviews)
- **debugger** (opus): Root cause analysis, hypothesis-driven investigation, fix recommendations
- **writer** (opus): Info collection, code snippet extraction, Markdown draft writing

> **Rule:** Any task that produces architecture documentation or a service README MUST be delegated to architecture-research-planner. Never write these files inline with Write/Edit tools.

> **Reviewer invocation:** always pass the Code Review Checklist at `~/.claude/skills/domains/quality-attributes/references/review-checklist.md` in the reviewer agent's prompt.

## Agent Output Register

Reference: `~/.claude/skills/domains/communication/SKILL.md` — the single source for the output register. It applies to the main conversation and to every agent's conversational output. Agent files carry a one-line summary plus a pointer to it; edit the skill, not the copies.

Summary: human-like register zero; technical content kept in full as scannable `<what> — <why>` lines; one sharp sentence of WHY per finding, always; conversation reserved for clarifications, blockers, and the prompts this file mandates (the `open <path>` question, commit-message and `progress.md` proposals, phase gates); when relaying an agent result, relay the substance and drop the agent's framing.

# Planning Structure

Reference: `~/.claude/skills/workflows/planning/`

**Directory structure:**
```
planning/
├── progress.md                      # Active work only: current issue, last 3 merged, next steps
├── reviews-orphan/                  # Fix reviews for unlinked work (uncommon; hand-managed)
├── <epic-slug>/                     # One folder per epic (slug derived from epic title)
│   ├── overview.md                  # Epic summary (About/Scope/Owner) + milestone roadmap
│   ├── reviews/                     # External MR reviews touching this epic
│   │   └── MR<N>-review.yaml        # Final published output only; intermediates deleted post-publication
│   └── milestone-XX-<name>/
│       ├── status.md                # Issue list with phase column + dependency diagram
│       ├── tickets/                 # YAML files for projctl create
│       └── issues/
│           └── <NNN-name>/          # One folder per issue — all reviews live here
│               ├── analysis.md      # Research output (Phase 1)
│               ├── design.md        # Design doc (Phase 2)
│               ├── design-review.md # Design review (Phase 3) — single file, always overwritten
│               ├── code-review.md   # Code review (Phase 5) — single file, always overwritten
│               ├── codex-review.md  # Codex review of our issue — single file, always overwritten
│               └── observed-failures.md  # Append-only ledger of failures that actually occurred + how each is covered
```

`observed-failures.md` also appears at `planning/reviews-orphan/<slug>/` for unlinked hotfixes. It is **exempt from the one-final-output convention** — it is an append-only ledger, never overwritten or consolidated, so each failure keeps its own entry and resolution.

The `<epic-slug>/` folder is instantiated automatically by `/review-mr` on first use. Once created, `/research` and `/design` write into it. You do not need to create it by hand. See `OVERVIEW-TEMPLATE.md` "When to instantiate" for the exact rules.

**Key principles:**
- `progress.md` = what's active right now (≤ 30 lines; no backlog lists)
- `status.md` = full milestone picture: all issues, phases, dependency order
- `issues/<NNN-name>/` = everything for one issue in one place, including all our own reviews (design/code/codex); filenames inside are generic (`design.md`, not `verifier-design.md`)
- `<epic-slug>/reviews/` = external MR reviews (MRs we're reviewing but don't own the underlying issue for); one epic subfolder per set of MRs. Never a top-level `planning/reviews/` (exception: `planning/reviews-orphan/` is permitted — see below).
- `reviews-orphan/` = fix reviews for work with no linked issue (hotfixes, sandbox experiments); hand-managed, not tracked in `progress.md`. No migration needed; `/start` leaves it in place.
- **One final published output per review.** No `-r<N>`, `-final`, or `-v2` filename suffixes anywhere in the tree. Every review-writing command overwrites its canonical file in place; git history is the retry log. Intermediate working files (review-requests, Codex raw output) are deleted immediately after the final artifact is published. **Exception:** when `/codex-review` is invoked standalone by the user (not from a higher-level command), the codex-review output is the terminal artifact — no intermediate to delete. The review-request is left in place for re-invocation.
- **`overview.md` doubles as a local epic cache.** For epics we don't actively work on but touch via external MR review, `overview.md` carries an "About" summary, "Scope" bullets, and "Owner" line sourced from `projctl load epic &N` so future readers have context without re-hitting GitLab. See `~/.claude/skills/workflows/planning/OVERVIEW-TEMPLATE.md` for the structure.

**Old format migration:** If a milestone folder contains a flat `design/` or `reviews/` subdirectory, or if a top-level `planning/reviews/` exists, it uses the pre-migration layout. `/start` detects this automatically and proposes a migration to `issues/<NNN-name>/` (for issue-scoped reviews) or `<epic-slug>/reviews/` (for external MR reviews) before loading context. Never read from old paths — migrate first. `planning/reviews-orphan/` is exempt from migration — preserve it as-is.

# Post-Write Actions

After writing certain files, always ask the user if they want to open the file with `open <path>` before continuing:

| File type | When to ask |
|-----------|-------------|
| Design docs (`planning/**/issues/*/design.md`) | After Phase 2 design doc is written |
| Design review reports (`planning/**/issues/*/design-review.md`) | After Phase 3 review is written |
| Code review reports (`planning/**/issues/*/code-review.md`) | After Phase 5 review is written |
| MR review YAML (`planning/<epic-slug>/reviews/MR*.yaml`) | After `/review-mr` YAML is written |
| Issue/Epic YAML files (any YAML created for `projctl create`) | After the YAML is written |
| Article brief (`planning/book/**/issues/*/brief.md`) | After `/write` in book-article mode writes the brief |

Ask exactly once per file, immediately after writing. Do not open automatically — always ask first. Ask the open-file question in isolation — do not combine it with a phase-advancement question or any other action prompt in the same message.

# CI Platform Management

**Tool:** `projctl` (Python package)

For ALL managerial tasks related to GitLab/GitHub, use `projctl`:
- Creating/updating issues, epics, milestones
- Creating merge requests (MRs) or pull requests (PRs)
- Loading ticket information (issues `#N`, epics `&N`, milestones `%N`, MRs `!N`)
- Searching issues, epics, and milestones by text/state
- Managing milestones: activate/close state, set due-date, assign issues to milestones
- Synchronizing planning folders with Google Drive
- Multi-platform workflow automation

**Usage Instructions:**
- Run `projctl --help` to see usage examples and find the full path to CLAUDE.md documentation
- The `--help` output includes a "Documentation:" section with the absolute path to comprehensive usage instructions
- Invoke via `/mr` and `/load` commands, which internally use projctl

**Critical rule:** If a required operation is not supported by projctl, extend it first (source at `~/projects/projctl`) rather than working around it with direct `glab` CLI or GitLab API calls. Never bypass projctl.

# Proprietary Information Policy

**Any information specific to paid/professional work** (company tools, internal project names, colleague names, team workflows, client-specific conventions, internal URLs, proprietary tooling) **must go into project memory files — never into this file.**

This file may be synced to GitHub or other public locations. Memory files (`~/.claude/projects/.../memory/`) are local only and safe for proprietary content.

**Rule:** When in doubt whether something is proprietary, put it in memory.

## `platforms/` files — mandatory pre-commit scan

Any file under `platforms/` is committed to a public GitHub repository. Before proposing or applying any commit that touches `platforms/`, run:

```bash
bash .git/hooks/pre-commit
```

The hook scans for `/home/<user>/work/` path leaks only. Removing project names, internal identifiers, and other proprietary nouns is a manual responsibility — see the Path exposure rules below. Fix every hit before committing. This rule applies to me (Claude) on every edit to `platforms/` — not only when the user asks for a scan.

**Path exposure rules for `platforms/` files:**
- `/home/*/projects/*` paths are acceptable (personal open project repos).
- `/home/*/work/*` paths are **strictly prohibited** — these are work-context repos that contain proprietary project names.
- All other identifiers (project names, component names, internal labels, colleague names) must be replaced with generic fictional equivalents: `src/pipeline/pipeline.cc`, `component::api`, `ProjectX`.
