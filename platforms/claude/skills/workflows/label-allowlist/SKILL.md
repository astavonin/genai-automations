---
name: label-allowlist
description: Shared pre-flight fragment. Reference this skill from commands that write GitLab labels (currently: /mr, /ticket) to fetch, cache, and enforce the project label allowlist before YAML generation.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, labels, projctl, pre-flight]
---

# Label Allowlist — Shared Fragment

Fetch the project label allowlist from `projctl` and constrain the caller's YAML `labels:` fields against it. The workflow does not depend on `projctl` rejecting unknown labels at submit; this pre-flight is the primary gate.

## When to Use

Include this fragment at the start of any command step that writes a `labels:` field to a YAML that will be handed to `projctl create` or `projctl create-mr`. Current callers:

- `/mr` — Step 3, before writing `planning/mr-draft.yaml`
- `/ticket` — Step 4, before writing `planning/<goal>/milestone-XX-<name>/tickets.yaml`

## Steps

### 1. Fetch the allowlist

Run:

```bash
timeout 30 projctl labels > planning/.label-allowlist.txt 2> planning/.label-allowlist.err
echo "exit=$?"
```

Stderr MUST be redirected to `planning/.label-allowlist.err` — the pre-feature-projctl detection in Step 2 keys on it and cannot succeed from stdout alone. Persisting the snapshot to `planning/.label-allowlist.txt` is mandatory. This gives:

- an observable check surface — a maintainer or test can verify the pre-flight fired by checking for the file
- a compaction-safe source of truth — the LLM's in-context memory can be lost across `/start` / `/implement` / `/complete` auto-compact boundaries; the file cannot
- a single artifact the caller shows to the user at the confirmation step

### 2. Branch on the exit code, then the file contents

Branches are ordered: **exit code is checked first, and non-zero exit codes take precedence over any file inspection.** The empty-file heuristic only applies inside the exit-0 branch. A non-zero-exit run that happens to leave `planning/.label-allowlist.txt` empty MUST NOT be confused with a legitimately empty allowlist.

**Pre-feature projctl — requires BOTH signals (exit code AND stderr substring):**

Both conditions must hold to classify a run as pre-feature. Either signal alone is not sufficient — exit code 2 is a generic Python-argparse code returned for many argument errors, and `invalid choice` may appear in unrelated stderr contexts.

Conditions (all must be true):

1. Exit code is 2 (nonzero required), AND
2. `planning/.label-allowlist.err` contains the substring `invalid choice`, AND
3. `planning/.label-allowlist.err` also references the `labels` subcommand (e.g. `argument.*labels`, `choose from ...` listing that omits `labels`, or a message naming `labels` explicitly)

If ALL three hold, the installed `projctl` does not implement `labels`. Degrade to trust-based: the caller MAY write `labels:` entries but MUST include a `⚠️ workflow-safety` block in the user's confirmation step:

```
⚠️  workflow-safety: label pre-flight unavailable
    reason: installed projctl does not implement `labels` (pre-feature)
    recovery: update projctl; user retains veto at YAML confirmation
```

The caller's YAML displays regardless; the user's confirmation is the sole gate in this branch.

If exit code is 2 but the stderr signals are absent, OR the stderr signals are present but the exit code is 0 or something other than 2: DO NOT classify as pre-feature. Fall through to the generic non-zero branch below. Silent misclassification into the trust-based branch is the failure this AND requirement prevents.

**Any other non-zero exit or timeout (exit ≠ 0 and not pre-feature):**

HALT the caller. Surface a `⚠️ workflow-safety` block per §8.2 in the platform CLAUDE.md:

```
⚠️  workflow-safety: label allowlist unavailable
    reason: `projctl labels` failed with exit <N>
    recovery: user must select from three options (retry / wait / omit) — do not proceed without a selection
```

Do NOT proceed silently. Present these three options to the user and wait for a selection before proceeding:

1. Retry after fixing `projctl labels`
2. Wait and retry later
3. Explicitly omit `labels:` for this run (must be user-selected, not caller-chosen)

The caller MUST NOT unilaterally choose option 3 — the omit-entirely path silently loses label metadata the user may have wanted and requires explicit user consent. The recovery line in the §8.2 block deliberately names the option-list rather than naming a single action, so the user reaches the choice regardless of whether they read the block or the options first.

**Exit code 0 — command succeeded:**

Only now inspect the stdout file. Match on explicit sentinel strings only; do not infer emptiness from prose shape:

- Read `planning/.label-allowlist.txt`.
- **Empty-allowlist sentinel match:** if the file contains any of the following exact strings, classify as empty allowlist:
  - `No allowed labels configured`
  - `(no labels configured)`

  On empty-allowlist classification, the caller MUST omit the `labels:` key entirely for every issue, epic, or MR generated in this run. Include the note "project has no configured allowlist — `labels:` omitted for every entry" in the caller's user-facing confirmation step.

- **Zero-byte file:** if the file is empty (zero bytes) with exit 0, classify as empty allowlist (same handling as sentinel match).
- **Otherwise (exit 0, no sentinel match, non-zero bytes):** proceed to Step 3 (match). The match step ignores header lines, group names, descriptions, and colors, so it tolerates variance in `projctl labels` output shape without a separate format-recognition heuristic. If the format changes drastically and no lines look like label names, Step 3 will simply find no matches, all `labels:` entries will be omitted, and the user will see this stated explicitly in the confirmation summary — a soft-fail-safe outcome rather than a silent misclassification.

**Reference — current `projctl labels` output shapes.** As of the time this fragment was written:

Empty allowlist (either sentinel present, exit 0):

```
No allowed labels configured. Showing default labels:

(no labels configured)
```

Non-empty allowlist (typical shape, exit 0):

```
Configured labels (from projctl.yaml):

Iteration::
  Iteration::1
  Iteration::2

type::
  type::feature
  type::bug

Ungrouped labels:
  Architecture & Research
  Backend integration
  CI
  ...
```

If a future `projctl` release changes the format substantially, update the sentinel list above rather than adding new heuristic branches.

### 3. Match every `labels:` entry against the snapshot

Every string placed into a `labels:` field (issue-level, epic-level, or MR-level) MUST match **byte-for-byte** — same case, spaces, punctuation — a label name in `planning/.label-allowlist.txt`. Match against the label name only; ignore header lines, section names, descriptions, and colors. `Infra & DevOps`, `infra & devops`, and `Infra&DevOps` are three distinct strings; only one (at most) is in the allowlist.

Never extrapolate from prior YAML files, never infer labels from the change's topic, never copy from a stale draft, never invent a name that "sounds right" from the shape of listed names.

If no listed label fits an entry, **omit the `labels:` key entirely** for that entry. Do not write `labels: []`, do not write `labels:` with no value. Include "no listed label fits" in the caller's confirmation summary.

### 4. Show the snapshot at the confirmation step

The caller MUST display `planning/.label-allowlist.txt` alongside the generated YAML at its user-confirmation step. The user's confirmation covers both the YAML labels and the allowlist they were checked against.

### 5. Cache-lifetime rule (confirmation-time entry point)

This fragment has a second entry point invoked at the caller's confirmation step. When the caller re-reads this file at that step, execute this section only.

Before showing the YAML to the user, check the snapshot for presence AND freshness using a portable idiom (must work on both GNU-coreutils and BSD `stat`; do NOT use `stat -c %Y` — that is GNU-only and breaks on macOS):

```bash
# Portable freshness check via find -mmin (POSIX-adjacent, works on GNU and BSD).
# Prints "fresh" if the file exists AND was modified in the last 5 minutes;
# prints "missing-or-stale" otherwise. Do not rewrite this using `stat` flags.
if [ -n "$(find planning/.label-allowlist.txt -mmin -5 2>/dev/null)" ]; then
  echo "fresh"
else
  echo "missing-or-stale"
fi
```

**Staleness bound:** the `-mmin -5` argument enforces a 5-minute freshness window. A skill run rarely spans 5 minutes between pre-flight and confirmation on the same file; a snapshot older than that is a signal that either the session was paused (in which case labels may have changed server-side) or the file is left over from a prior run entirely.

Re-run Steps 1 and 2 in full before showing the YAML in either case:

- **Missing** — the file does not exist (compaction pruned it, working directory changed, another process removed it).
- **Stale** — the file exists but was modified more than 5 minutes ago.

`find -mmin -5` returns the file if it satisfies both conditions in one call; a `missing-or-stale` result means neither condition was satisfied and the snapshot must be regenerated.

Never fall back to an LLM-remembered version of the allowlist — treat the snapshot file as the sole source of truth, and refresh it when it's older than the bound. If the snapshot check prints `fresh`, proceed to display it alongside the YAML.

Callers MUST invoke this fragment twice: once at the pre-flight step (Steps 1–4 fire) and once at the confirmation step (only Step 5 fires). The pre-flight invocation must precede the YAML generation; the confirmation invocation must precede the user's YAML confirmation.

## Residual failure paths (not covered)

- **`labels.default` in projctl config.** This fragment verifies only what the workflow writes. Labels merged in by `projctl` from the `labels.default` config field are NOT verified here. If `projctl create` / `projctl create-mr` still rejects at submit after a clean workflow-side run, check `labels.default` in the projctl config against `projctl labels` output.
- **Projctl-side allowlist enforcement.** If and when `projctl create` / `projctl create-mr` starts rejecting unknown labels at submit, that becomes a defense-in-depth backstop; this pre-flight remains the primary gate — do not rely on the tool to catch fabrication.
