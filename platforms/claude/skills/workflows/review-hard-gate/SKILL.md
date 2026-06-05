---
name: review-hard-gate
description: Shared fragment — HARD GATE block that must appear before launching review agents + codex-flow. Caller specifies whether the test-coverage agent (Step F) is included.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, gate, agents]
---

# Review Hard Gate — Shared Fragment

Mandatory gate block that prevents sending the agent launch message until all required calls are present in a single message. Prevents the common mistake of launching Claude agents before codex-flow is ready.

## Caller Must Specify

- **`test_coverage`** — `yes` (review-code, review-mr) or `no` (review-design, review-fix). Determines whether the test-coverage agent (Step F) is required in addition to the 3 reviewers.

## Gate Block to Include (verbatim, before the agent launch step)

**When `test_coverage = yes`:**

> **🚫 HARD GATE — do not send this message until BOTH conditions are met:**
> 1. All Agent calls (3 reviewers + test-coverage) are present in this message.
> 2. The `codex-flow` Bash call (`run_in_background: true`) is present in this message.
>
> **No justification overrides this gate.** If `codex-flow` cannot launch, do not send the agent calls — surface the blocker first.

**When `test_coverage = no`:**

> **🚫 HARD GATE — do not send this message until BOTH conditions are met:**
> 1. All Agent calls (3 reviewers) are present in this message.
> 2. The `codex-flow` Bash call (`run_in_background: true`) is present in this message.
>
> **No justification overrides this gate.** If `codex-flow` cannot launch, do not send the agent calls — surface the blocker first.
