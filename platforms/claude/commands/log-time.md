---
name: log-time
description: Find the issues worked on today across every tracked repository and log the working day against them with projctl timelog. Evidence comes from projctl activity; hours are allocated to the least-logged issue.
---

# Log Time Command

Find the issues worked on today across every tracked repository, allocate the unlogged remainder of the working day between them, and post the result with `projctl timelog`.

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

An issue commonly appears more than once, corroborated by several sources. That is information, not duplication — report it, then deduplicate by id before allocating.

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

Read `issues[]`, each entry carrying `id`, `via` and `count`, and keep the repository alongside each: `projctl` resolves its project from the working directory, so every later call must run with that repository as its working directory. **Deduplicate by `id`** — one issue found three ways is one issue.

Treat a `via` of `review` as a merge request. `projctl timelog add` takes `!<N>` for an MR and `<N>` or `#<N>` for an issue, so the prefix has to survive into Step 5.

**`unattributed` is reported, never dropped.** It carries the events and files that matched no ticket, plus the branch they were on. A day's work that produced nothing attributable is exactly where a silent zero would be wrong.

### Step 2: Check what is already logged

**One call, from any tracked repository.** The report is scoped to the user, not to the working directory's project — it lists every entry across all projects for the date, so calling it once per repository returns the same output each time.

```bash
cd "<any-tracked-repo>" && projctl timelog "<date>"
```

Only `timelog add` is project-scoped and needs the owning repository as its working directory.

### Step 3: Allocate the shortfall

Subtract what Step 2 reported from `hours_per_day`. **The shortfall, not the whole day, is what gets allocated** — a day already carrying six logged hours has two left, and proposing eight would double-count the six.

If the shortfall is zero or negative, report what is already logged and stop.

**One hour is the minimum loggable unit, and the only unit.** Durations are whole hours; a half-hour share cannot be posted, so the shortfall is allocated in units of one hour rather than divided.

Hand out the shortfall one hour at a time. **Each hour goes to whichever active ticket has the least time against it so far**, counting what Step 2 reported plus anything already handed out in this loop. Ties break toward the ticket found earliest in Step 1.

This levels rather than divides, which is what the 1h floor forces: when there are fewer hours to give than tickets — two hours across three tickets — an equal split would put every share below the minimum and post nothing. Levelling instead sends those hours where the record is thinnest, which is normally the ticket worked on today with nothing logged against it yet.

A ticket that receives no hour is still **reported** as worked-but-unlogged. It was found on real evidence, and a silent omission is how a day's work disappears.

No weighting beyond that. `count` says how many files or events fired, not how long anything took — an issue with seven planning files and one with one are not thereby in a 7:1 ratio of hours, and treating them so would dress a guess as a measurement.

### Step 4: Propose, and wait

Print one line per ticket — repository, ticket, evidence, proposed duration — plus anything unattributed and anything already logged. Then **stop and wait for explicit approval.** The user may adjust any line before anything is posted.

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
- Levelling to the least-logged ticket is a stated convention, not a measurement. It is defensible because it is transparent — the user sees every line and can correct it before anything is posted — and that is the whole of its claim.
