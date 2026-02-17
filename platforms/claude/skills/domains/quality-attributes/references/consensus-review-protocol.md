# Consensus Review Protocol

A shared multi-agent review mechanism used by all `/review*` commands.

## How It Works

Three independent reviewer agents evaluate the subject in parallel. A finding is only
included in the final output if **at least 2 of 3 agents** independently flag it.
The consensus severity is determined the same way: the severity level that **at least
2 agents agree on**. If all three differ, use the middle severity (e.g., Critical/High/Low
→ use High).

## Protocol Steps

### Step A: Launch 3 Independent Reviewers in Parallel

Spawn three **reviewer (opus)** agents simultaneously. Each agent:
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

This consolidated list is handed back to the calling command, which formats it
according to its own output format (YAML for `/review-mr`, markdown for `/review-code`
and `/review-design`).

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
