---
name: issue-folder-resolve
description: Shared fragment — resolves `<issue-folder>`, the single canonical path for an issue's planning artifacts, including the orphan fallback for unlinked work. Read by any command that reads or writes a file inside the issue folder.
allowed-tools: Bash, Glob, Grep, Read
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, planning, paths, resolution]
---

# Issue Folder Resolution — Shared Fragment

Several commands read and write the same files inside an issue's folder. If two of them derive the path differently, the writer and the reader miss each other and the miss is **silent** — a missing file reads as "nothing to do", not as an error. This fragment defines one procedure so every command lands on the same string.

## Canonical Form

```
planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>
```

This spelling is authoritative. Older files use `planning/<goal>/milestone-XX/issues/<NNN-name>` — `<goal>` and `<epic-slug>` mean the same thing, and the milestone folder does carry a `-<name>` suffix on disk. When you see the older spelling, resolve against the canonical form.

## Procedure

1. **Extract the issue number.** Parse `Ref #<N>` from the current branch's last commit message, or from the branch name (`feature/<N>-*`, `fix/<N>-*`). If neither yields a number, ask the user. If the user says "none", "unlinked", or the work is a hotfix or sandbox experiment, go to Orphan Fallback.
2. **Confirm it exists:** `projctl load issue <N>`.
3. **Match on disk:** find `planning/*/milestone-*/issues/<N>-*/`. Use the match as `<issue-folder>`.
4. **If no folder matches,** resolve the epic (from `## Epic &<M>` in the issue output) and milestone locally. Commands that own the issue lifecycle (`/research`, `/start`) may create it; every other command bails with an actionable error rather than inventing a folder.
5. **Corroborate against any ledger already on disk.** Not every repo uses the milestone/issues shape — some keep flat `planning/<epic-slug>/<work-slug>/` folders — so a writer may have used a path this procedure would not re-derive.

   ```bash
   ROOT=$(git rev-parse --show-toplevel) && find "$ROOT/planning" -name observed-failures.md
   ```

   A hit replaces your derived path **only if it corroborates the identity resolved above** — its path contains the issue number `<N>`, or the orphan slug from the fallback below. A hit that matches neither belongs to different work: ignore it and keep your derived path.

   **Never adopt a ledger merely because it is the only one in the repo.** Identity, not scarcity, is what makes it yours. At adoption time a repo often holds exactly one ledger, and binding to it unconditionally would point every command at whichever issue happened to get there first — writing reviews into a stranger's folder, appending entries to a stranger's ledger, and reporting `PASS` for work that has no entry.

   If several hits corroborate, ask the user rather than guessing.

6. **Echo the resolved path** on one line so downstream commands in the same session reuse the exact string:
   ```
   Issue folder: planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>
   ```

## Orphan Fallback

For work with no linked issue — hotfixes on `main`, unticketed CI fixes, sandbox experiments:

```
planning/reviews-orphan/<slug>
```

**Any command that writes into the orphan path may create it,** including `planning/reviews-orphan/` itself. Step 4's "do not invent a folder" rule governs *issue* folders, whose names encode an issue number this command cannot invent; an orphan folder is derived deterministically from the branch and has no such constraint.

**`<slug>` is derived from the branch name**, not from a description: strip any `feature/`, `fix/`, `hotfix/`, or `chore/` prefix, lowercase, and replace every run of non-alphanumeric characters with a single `-`.

**Reuse before you mint.** The slug is pinned at first write. Always look for an existing folder first — a slug recomputed later must resolve to the folder the earlier command actually wrote to.

```bash
BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || { echo "detached HEAD — ask the user for the slug"; exit 1; }
BASE=$(echo "$BRANCH" | sed -E 's#^(feature|fix|hotfix|chore)/##' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')
[ -n "$BASE" ] || { echo "branch name has no alphanumeric content — ask the user for the slug"; exit 1; }

case "$BASE" in
  main|master|develop|trunk)
    # Long-lived branch: suffix so the folder is not literally named for the branch. Reuse it.
    # Match only the minted <base>-<short-sha> shape, so a real branch named e.g. "main-x"
    # cannot be mistaken for this branch's incident folder.
    ORPHAN="$(git rev-parse --show-toplevel)/planning/reviews-orphan"
    # -name (not -regex): BSD/macOS find defaults -regex to basic REs where "+" is literal.
    MATCHES=$(find "$ORPHAN" -maxdepth 1 -type d -name "$BASE-*" 2>/dev/null \
              | while read -r d; do case "${d##*-}" in *[!0-9a-f]*) ;; *) echo "$d";; esac; done)
    COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
    if [ "$COUNT" -eq 1 ]; then SLUG=$(basename "$MATCHES")
    elif [ "$COUNT" -gt 1 ]; then echo "several candidates — ask the user which:"; echo "$MATCHES"; exit 1
    else SLUG="$BASE-$(git log -1 --format=%h)"   # mint once, then reuse
    fi ;;
  *) SLUG="$BASE" ;;
esac
echo "$SLUG"
```

The suffix must be **pinned, not recomputed**: `git log -1` moves with every commit, including the `--amend` that Phase 7 mandates for fixes, so re-deriving it in a later session would point at a folder that does not exist and the gate would report a false `N/A`. Reuse-then-mint pins it at first write.

**Know what this does not give you.** The folder is still one per long-lived branch, not one per incident — the suffix is a stable name, not a partition. Several unticketed hotfixes on `main` share a ledger, so if a later fix never gets an entry written, the gate sees the earlier resolved entries and reports `PASS` rather than `N/A`. The mechanical check cannot detect a missing entry on a shared ledger; the agent-level checks do — `/review-fix` Step F and the checklist's Test Quality Pass Step 3 rate an observed failure with no entry as High. Do not treat `PASS` on an orphan ledger as proof that this fix was recorded.

The `#` delimiter is load-bearing: `|` is the alternation operator inside the group, so using it as the `s` delimiter makes sed abort with `unknown option to 's'` and emit nothing — which silently yields an empty slug and a path like `planning/reviews-orphan//observed-failures.md`.

A description-derived slug is **not** acceptable — two commands describing the same fix differently produce two folders and lose each other's files. On a detached HEAD the branch name is empty; ask the user for the slug rather than guessing.

Echo the resolved path the same way:
```
Issue folder (orphan): planning/reviews-orphan/<slug>
```

## Notes

- Resolve **once** per command invocation, before the first read or write inside the folder — not per artifact.
- When a command hands off to another (`/diagnose` → `/implement`, `/ci-debug` → `/review-fix`), pass the resolved path explicitly. Re-deriving it in the receiving command is what produces mismatches.
- `planning/reviews-orphan/` is hand-managed and not tracked in `progress.md`. It is exempt from the old-format migration `/start` performs.
