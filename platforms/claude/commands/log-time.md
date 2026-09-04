---
name: log-time
description: Find the issues worked on today across every tracked repository and log the working day against them with projctl timelog. Evidence comes from projctl activity; hours are split by what that evidence says each ticket actually cost.
---

# Log Time Command

Find the issues worked on today across every tracked repository, split the unlogged remainder of the working day between them according to what the evidence says each one cost, and post the result with `projctl timelog`.

## Usage

```
/log-time [<YYYY-MM-DD>]
```

Defaults to today. A date argument logs for an earlier day, which both `projctl activity` and `projctl timelog add --date` accept.

## Where the evidence comes from

**`projctl activity` gathers it. This command does not.** Reflog parsing, mtime comparison, branch and path matching all live in tested Python — an earlier version of this file prescribed the same logic as shell, and two agents following that prose reached different answers about the same repository on the same day. Anything resembling `git reflog | grep` belongs in `projctl`, not here.

The four sources it reports, as `via` values:

| `via` | Evidence | Note |
|---|---|---|
| `planning` | a file under `planning/**/issues/<N>-<slug>/` modified on the date | strongest — independent of branch and commit, so it catches design and review days |
| `reflog` | `Ref #<N>` in a `commit` or `commit (amend)` entry | a day's work is usually one commit amended repeatedly, which `git log` cannot see |
| `review` | `planning/<epic>/reviews/MR<N>-review.yaml` modified on the date | an **MR**, not an issue |
| `branch` | branch `<type>/<N>-<slug>`, only where a file was modified on the date | weakest; the file is the evidence, the branch only the label |

An issue commonly appears more than once, corroborated by several sources. That is information, not duplication — report it, then collapse on the Step 1 key before allocating.

## Configuration

The repository root lives outside this file, in `~/.config/projctl/worktree.yaml`:

```yaml
root: /absolute/path/to/repository/root
hours_per_day: 8
```

Repositories are discovered as `<root>/*/` containing a `projctl.yaml` — the same file `projctl` needs to resolve the project, so a directory without one could not be logged against anyway and is skipped rather than named. If the config is absent, stop and print the schema above; do not guess a root.

## Actions

### Step 1: Collect the day's evidence

One call per repository:

```bash
cd "<repo>" && projctl activity "<date>" --json
```

It exits `0` whether or not it found anything — no activity is a result, not an error. Non-zero means a real failure and stops the run.

Read `issues[]`, each entry carrying `id`, `via` and `count`, and keep the repository alongside each: `projctl` resolves its project from the working directory, so every later call must run with that repository as its working directory. **Collapse to one proposal line per `(repository, target kind, id)`, keeping every `via` and its `count`** — one issue found three ways is one issue reported with three sources of evidence, not one. All three parts of the key are load-bearing: `via: review` names a merge request and every other `via` names an issue, and GitLab numbers the two sequences independently, so issue `#7` and MR `!7` are different objects; issue numbers also repeat across repositories. Collapsing on the bare number merges targets Step 5 must post to separately.

Treat a `via` of `review` as a merge request. `projctl timelog add` takes `!<N>` for an MR and `<N>` or `#<N>` for an issue, so the prefix has to survive into Step 5.

**`unattributed` is reported, never dropped.** It carries the events and files that matched no ticket, plus the branch they were on. A day's work that produced nothing attributable is exactly where a silent zero would be wrong.

### Step 2: Check what is already logged

**One call, from any tracked repository.** The report is scoped to the user, not to the working directory's project — it lists every entry across all projects for the date, so calling it once per repository returns the same output each time.

```bash
cd "<any-tracked-repo>" && projctl timelog "<date>"
```

Only `timelog add` is project-scoped and needs the owning repository as its working directory.

### Step 3: Split the shortfall by what the day actually cost

Subtract what Step 2 reported from `hours_per_day`. **The shortfall, not the whole day, is what gets allocated** — a day already carrying six logged hours has two left, and proposing eight would double-count the six.

If the shortfall is zero or negative, report what is already logged and stop.

**One hour is the minimum loggable unit, and the only unit.** Durations are whole hours; a half-hour share cannot be posted, so each ticket's share is zero hours or a whole number of hours — never a fraction.

**Read the evidence and judge what each ticket cost. That judgement is the allocation** — there is no equal split and no levelling rule to fall back on. Weigh which `via` sources fired for a ticket and how many times — `id`, `via`, and `count` are what Step 1 returns, and that is all the judgement has to work with:

| Signal | Reads as |
|---|---|
| `planning` hits, several of them | design or review work — toward most of a day |
| `planning` hits, one | some planning-doc activity — a partial day unless corroborated |
| `reflog` hits, several of them | implementation iteration — several amends read as most of a day |
| `reflog` hits, one | a single commit — an hour |
| `review` hits | reviewing an MR — a pass through the diff, closer to an hour than a full day unless several |
| several `via` sources on one line | the ticket carried the day: research, then implementation |
| a single `branch` hit, nothing corroborating | the weakest evidence there is — an hour, and say that it is thin |

`count` is an input to that judgement, never a formula. Seven planning hits against one is not a 7:1 ratio of hours — count says how often a source fired, not how much any single touch was worth.

Two constraints on the result: the shares are whole hours summing to the shortfall, and it is each ticket's **day total** — Step 2's existing entries plus its new share — that has to look right, not the new share in isolation.

When the shortfall has fewer hours than tickets, the hours go where the day's weight was rather than being spread until nothing meets the floor. Where two tickets carry equal weight, break the tie toward whichever was found earliest in Step 1. A ticket that receives no hour is still **reported** as worked-but-unlogged. It was found on real evidence, and a silent omission is how a day's work disappears.

### Step 4: Propose, and wait

Print one line per ticket — repository, ticket, evidence, proposed duration, and the one clause of reasoning behind that duration — plus anything unattributed and anything already logged. The reasoning is what makes the split correctable: a share the user disagrees with is only arguable if they can see what it was based on. Then **stop and wait for explicit approval.** The user may adjust any line before anything is posted.

Approval is for the numbers shown. A conversational acknowledgement is not approval; see Definitions in `~/.claude/CLAUDE.md`.

### Step 5: Post

Dry-run first, from the owning repository:

```bash
cd "<repo>" && projctl timelog add <ticket> "<duration>" --date "<date>" --dry-run
```

`<ticket>` is `<N>` for an issue and `!<N>` for a merge request. If the preview matches the approved line, run it again without `--dry-run`. Report what was posted, one line per ticket.

On any failure, stop and report — do not retry with a different duration or a different ticket.

## Constraints

- **This command posts to GitLab.** Steps 1–4 are read-only and safe to run at any time; Step 5 is the only one that writes, and it runs only after explicit approval of the exact numbers.
- **Evidence gathering belongs in `projctl activity`.** If this command needs a signal that command does not report, extend `projctl` — it has tests and this file does not. Reimplementing the logic here is what produced two agents disagreeing about the same day.
- `projctl activity` reads only local state. Work done on another machine, in a repository outside the configured root, or entirely in a browser is invisible to it, and the command says so rather than silently spreading the day across whatever it happened to find.
- The split is a judgement about a day, not a measurement of it. Nothing here times anything; the evidence says which tickets were worked and roughly how hard, and the rest is inference. It is defensible because it is transparent — every line carries the reasoning that produced it, and the user corrects it before anything is posted — and that is the whole of its claim.
