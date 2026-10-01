---
name: round-verdict
description: Shared fragment — the unprompted next-round verdict every review command and fix loop states at the end of a run. Defines the line's form, the signals it rests on, and why it is volunteered rather than requested. Read by review-code, review-design, review-spec, review-article, and the three *-fix-loop commands.
allowed-tools: Read
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, loop, decision]
---

# The Next-Round Verdict — Shared Fragment

**This file is the single source for the rule.** Callers read it and state the line; they do not restate the signals. Four hand-authored copies of this rule diverged in the commit that created them, which is why it is a fragment.

## The line

One line, at the end of the run's conversational report:

```
Another round: yes|no — <reason>
```

**State it unprompted.** Volunteer it whether or not anyone asks — the point is that the call is made and stated, not that it is requested. A run that omits it is caught by the reader, not by a test: the operator asks for the call, as they did before this line existed. That recovery is cheap, which is why the line is stated in each message template rather than pinned by assertions — three review rounds established that greps over prose cannot pin what this rule means.

`yes` and `no` are the whole vocabulary. A third value makes the line unscannable, which is the only thing it has going for it.

## What the reason rests on

Name the signal that decided it. A reason that names none — "looks fine", "seems worthwhile" — satisfies the form and carries nothing.

| Signal | Reads |
|---|---|
| Every fix proven by execution | **a gate that exists and ran** — a suite whose assertion count moved, a mutant that reddened, a red-then-green. Not a claim in the fix response: a fix pass can manufacture a gate, and a text-presence assertion will then defend it |
| The fix added mechanism rather than subtracting it | `doc-metrics` `TOTAL` before and after, `git diff --numstat`, or the fix pass's own per-finding report |
| The contract the fix touched is parsed by more than one consumer | the fix pass's per-finding report, which states whether a fix touched a symbol, heading or config value read at more than one site |
| What remains is Low or advisory | the report's own severity sections |

The first three presume a fix pass has run. **On a first review pass only the last applies**, and the reason says so rather than inventing the others.

The evidence behind these signals is `planning/genai-automations/stream-loop-control.md` in the `genai-automations` working tree. It is not read at run time and does not resolve elsewhere — the signals above are self-contained, and the pointer is for a reader who wants the record.

## Who states it

Every command that ends a review cycle with a conversational report: `/review-code`, `/review-design`, `/review-spec`, `/review-article`, and the Step 5 output of `/review-code-fix-loop`, `/review-design-fix-loop`, `/review-article-fix-loop`.

A fix loop states it at **three** exits, each of which carries the line in its own message template rather than inheriting it from prose: Step 5's `Output:` block, and the `### Cap-pause` and `### Stall stop` blocks. The last two matter most — they are where a human decides whether to continue — and they do not route through Step 5, so a rule stated only there would never reach them.

**Out of scope, recorded so the absence is a decision rather than an oversight:**

- `/review-mr` — its output is a YAML posted to the merge request, not a conversational report; there is no reader to volunteer a verdict to.
- `/review-fix` — reviews one fix, not a cycle, and has no between-rounds step to attach to.
- `/review-iterate` — runs one unconditional final sweep by design. Its divergence is recorded in `~/.claude/skills/workflows/review-output-format/SKILL.md` → Assessment Criteria as known and not licensed; giving it a verdict would imply a choice it does not offer.

Whoever adds a review command classifies it here — as a caller above or as out of scope with its reason — and in the caller list in `tests/verify-config-consistency.sh`. The condition is that a command ends a review cycle, not its position in any count: this section classifies every `review-*.md` command. (`tests/verify-config-consistency.sh` reads this sentence.)
