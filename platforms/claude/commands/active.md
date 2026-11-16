---
name: active
description: Short status for every active task — local planning state plus live in-session work, no tracker calls
---

# Active Command

Answer one question: **what is in flight right now, and what is each thing waiting on.**

This is a read. It spawns no agents, re-runs no gates, writes nothing, and makes no tracker call. It is cheap by design — the user invokes it to re-orient, often after a context break, and an `/active` that costs a minute of tool calls defeats its purpose.

## Sources, in order

**1. Live session state — check this first, because no file holds it.** This is the half a planning-file read cannot answer and is usually what the user most wants:

- Background agents and tasks still running, and what each was asked to do. If a notification has not arrived, the agent is running and its results are unknown — say that, never predict them.
- `git status --porcelain` and the delta against the last commit: uncommitted work is active work.
- Gate results observed **in this session** (build, test, lint exit codes), with their provenance — see Provenance below.

**2. `planning/progress.md`, the Active section only.** Never grep the whole file: it also carries closed-out entries and a Discovered-work list, and a line belonging to a neighbouring entry answers nothing about the current branch.

```bash
awk '/^## Active/{f=1;next} /^## /{f=0} f' planning/progress.md
```

**3. The milestone `status.md`** for the phase column and the issue set. Resolve the planning shape from disk rather than assuming three layers — see `~/.claude/CLAUDE.md` → Planning Structure.

**4. The issue folders of anything active** — a review file's `**Status:**` marker, an `observed-failures.md` entry still unresolved, a `design.md` still `Draft`. These decide what a task is blocked on, which is the column that matters most.

**No tracker call.** `projctl load` and `projctl search issues` hit the network and answer about live remote state — merged, pipeline, comments, assignee. A status request is about our own work in progress, which the local tree already records. If a row genuinely needs a live field, mark it and offer the call in one line (`Local only — <what is missing>. Query the tracker?`); do not make it silently and do not silently omit it.

## Output

One table, one row per active task, most active first. Columns: the task, and its state.

Each state cell carries what the task is waiting on, not a description of what it is. "Awaiting `/review-design`" beats "design phase". A blocked row names the blocker. A running row says what is running and that results are unknown.

**Hard limits:**

- **One row per task. No row longer than two sentences.**
- **Nothing that is not active.** Completed work belongs in `progress.md`, not here. A row whose only content is "done" earns a single word or no row at all.
- **No preamble, no narration, no summary paragraph after the table.**
- **Name the commands the user must invoke.** The AI never auto-advances a phase, so a row sitting at a gate is waiting on *the user* — say which command. This is the single most useful thing a status can carry.

**Provenance is mandatory on any gate or test number.** Distinguish a result observed in this session from one an agent reported, because an agent's reported success has twice turned out to be a compound command's exit status rather than the operation's. Write "verified this session" or "reported by the implementing agent" — never an unattributed green.

**Flag staleness rather than hiding it.** If `progress.md`'s `**Last Updated:**` predates work that has visibly happened, say so in one line — a status built on a stale file is worse than no status, and `progress.md` is updated only on explicit confirmation, so drift is expected.

After the table, add findings **only** when they change what to do next: a discovered blocker, a contradiction between two sources, a result that invalidates an earlier conclusion. Two or three lines at most, each a fact. Where there is nothing of that kind, the table is the whole answer.

## What not to do

- Do not re-run `./dev.sh build`, `test`, `itest` or `lint` to freshen a number. Report the last observed result with its provenance, and say it is the last observed result.
- Do not open a review, a design doc or an analysis in full to summarise it. Read its status marker and its blocking fields.
- Do not update `progress.md` or `status.md`. Those need explicit user confirmation and this command does not ask for it.
- Do not propose the next phase. Naming which command a row awaits is reporting; suggesting the user run it is advancing, and the two-part authorization test in `~/.claude/CLAUDE.md` → Critical Rules applies.
