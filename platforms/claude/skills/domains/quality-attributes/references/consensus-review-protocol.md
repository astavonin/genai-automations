# Consensus Review Protocol

A shared multi-agent review mechanism used by all `/review*` commands.

## How It Works

Three independent reviewer agents evaluate the subject in parallel. A finding is only
included in the final output if **at least 2 of 3 agents** independently flag it.
The consensus severity is determined the same way: the severity level that **at least
2 agents agree on**. If all three differ, use the middle severity (e.g., Critical/High/Low
→ use High).

## Protocol Steps

### Step A: Launch 3 Independent Reviewers and Codex in Parallel

Spawn three **reviewer (opus)** agents and Codex simultaneously. Codex is independent of the
Claude agents and does not need to wait for them — launching all four at once minimises wall-clock
time. Each Claude agent:
- Receives the same input: the subject under review + MR/design context (title, description)
- Receives: `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- Works **independently** — no shared state, no knowledge of other agents' outputs
- Produces a raw findings list: each finding has a `title`, `severity`, and `description`

Severity scale (same for all agents):
- `Critical` — will definitely fail, crash, or cause data loss
- `High` — significant correctness or security issue
- `Medium` — notable quality concern (test gaps, maintainability)
- `Low` — minor suggestion

### Step B: Aggregate — Issue Consensus

Group findings from all three agents by topic. Two findings refer to the same issue if they
describe the same root cause in the same code location (fuzzy match on concept, not wording).

**Inclusion rule:** include a finding only if **2 or more agents** flagged it.

Discard any finding that only 1 agent raised.

### Step C: Aggregate — Severity Consensus

For each included finding, collect the severities reported by the agents that flagged it:

| Votes | Rule |
|-------|------|
| 2/2 or 3/3 agree | Use agreed severity |
| 2/3 agree | Use the agreed severity |
| All 3 differ | Use the middle severity (sort Critical→High→Medium→Low, pick middle) |

### Step D: Produce Consolidated Findings List

Output: a deduplicated list of findings, each with:
- Consensus `title` (synthesize from agreeing agents)
- Consensus `severity`
- `description` — synthesized explanation of why the issue exists
- `location(s)` — from whichever agent(s) identified the specific code site
- `fix` — synthesized recommendation (where agents agree on the approach)

### Step E: Codex Cross-Model Verification

Codex runs in parallel with Step A (not after Step D). Once both the Claude consensus (Steps B–D)
and the Codex output are available, cross-aggregate them.

Run Codex via Bash from the project's working directory:

**For design/code reviews:**
```bash
{ printf "DO NOT make any changes. Only print your findings.\n\nReview the following for quality attributes (supportability, extendability, maintainability, testability, performance, safety, security, observability). List findings with severity Critical, High, Medium, or Low. Be concise.\n\n"; cat <subject-file>; } | codex exec -
```

**For MR reviews:**
```bash
codex review "DO NOT make any changes. Only print your findings. Review for bugs, security issues, logic errors, and standards compliance. Rate each finding Critical, High, Medium, or Low. Be concise."
```

**Cross-aggregate the results:**

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** Codex | Mark as **✓ Corroborated by Codex** |
| Claude consensus only | Include as-is (already filtered by 2/3) |
| Codex only | Include separately under **"Codex-only findings"** |

Two findings refer to the same issue if they describe the same root cause at the same code location (fuzzy match on concept, not wording).

The final output handed to the calling command contains:
1. Consensus findings (with corroboration tags where applicable)
2. Codex-only findings (separate section, labeled clearly)

## What Each Agent Should NOT Flag

To keep signal high, instruct each agent to skip:
- Pre-existing issues not introduced by the change under review
- Subjective style preferences
- Potential bugs that depend on specific inputs without clear evidence
- Nitpicks a senior engineer would not raise in a review

## Notes

- Each agent must be told the same context (title, description, diff or design doc)
- Agents must not be shown each other's output before Step B
- The aggregation (Steps B–C) is performed by the main conversation, not by a subagent
- Step E (Codex) runs after the Claude consensus, also in the main conversation via Bash
