#!/usr/bin/env bash
# verify-fix-mr-git-contract.sh — regression tests for the git and projctl premises
# `/fix-mr`'s Step 5 (Fix Chain) and Step 6 (Post) turn a guard or a predicate on.
#
# `fix-mr.md` is Markdown an agent reads, not a script a harness runs, so nothing here pins its
# text — that is tests/verify-config-consistency.sh's job. This suite hosts the underlying git
# and projctl behaviour the Fix Chain and Post steps' prose depends on: a scratch `git init`
# repository with a bare remote for the git rows, and a `projctl` stand-in on PATH for the
# predicate rows. No agent, no network, no real GitLab.
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

GREP=/usr/bin/grep

command -v git >/dev/null 2>&1 || { echo "FAIL: git is not installed."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is not installed — required by the predicate rows' JSON fixture reader."; exit 1; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "FAIL: PyYAML is not installed — required by the batch-validation predicate rows (Step 5a stand-in)."; echo "      Install it before running this suite: pip install pyyaml"; exit 1; }

# Bump when adding or removing an assertion — same self-check convention as
# verify-config-consistency.sh and verify-review-pack.sh.
EXPECTED_TESTS=24

TMPDIR_ROOT=$(mktemp -d) || { echo "FAIL: mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# A global core.hooksPath (or system-wide config) would redirect every scratch repo's hooks
# elsewhere, reddening the pre-receive-hook row (test 7) on a correct, unmutated corpus — this
# suite must not depend on the operator's own git configuration.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }

echo "verify-fix-mr-git-contract.sh"
echo "scratch root: $TMPDIR_ROOT"

# new_repo <case-name>: a fresh bare remote at "$d/origin" plus one working clone-shape
# checkout at "$d/work", tracking a branch named "source" one seed commit deep and already
# pushed — the shape every guard and amend/push row starts from.
new_repo() {
    local name="$1" d
    d="$TMPDIR_ROOT/$(printf '%s' "$name" | tr -c 'a-zA-Z0-9' '_')"
    mkdir -p "$d/origin" "$d/work"
    git init --bare -q "$d/origin"
    git -C "$d/work" init -q -b source
    git -C "$d/work" config user.name 'Operator'
    git -C "$d/work" config user.email 'operator@example.com'
    git -C "$d/work" remote add origin "$d/origin"
    printf 'seed\n' > "$d/work/file.txt"
    git -C "$d/work" add file.txt
    git -C "$d/work" commit -q -m seed
    git -C "$d/work" push -q origin source
    printf '%s' "$d"
}

# recheck_tree <repo> <recorded-paths>: the amend's pre-flight tree check — every tracked
# modified or staged path must sit in the space-separated recorded set.
recheck_tree() {
    local repo="$1" recorded=" $2 " path
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$recorded" in
            *" $path "*) : ;;
            *) return 1 ;;
        esac
    done < <(git -C "$repo" diff --name-only HEAD; git -C "$repo" diff --name-only --cached HEAD)
    return 0
}

echo "== Unit: guards, amend, and the one push =="

# 1: the authorship guard reads %ae, which `git commit --amend` preserves while the
# committer changes under it — the property the guard's comparison relies on.
d=$(new_repo author_preserved)
git -C "$d/work" config user.email 'other@example.com'
git -C "$d/work" config user.name 'Other Committer'
git -C "$d/work" commit -q --amend --no-edit
author_email=$(git -C "$d/work" log -1 --format='%ae')
committer_email=$(git -C "$d/work" log -1 --format='%ce')
if [ "$author_email" = "operator@example.com" ] && [ "$committer_email" = "other@example.com" ]; then
    pass "git commit --amend preserves the amended commit's author email while replacing the committer"
else
    fail "git commit --amend preserves the amended commit's author email while replacing the committer" \
         "author=$author_email committer=$committer_email"
fi

# 2: the clean-tree guard's exact predicate, and git add by name — a staged or unstaged tracked
# modification fails it, an untracked file alone does not, and the amend stages only the former.
d=$(new_repo clean_tree_guard)
printf 'changed\n' >> "$d/work/file.txt"
git -C "$d/work" diff --quiet HEAD; unstaged_rc=$?
git -C "$d/work" checkout -q -- file.txt

printf 'changed\n' >> "$d/work/file.txt"
git -C "$d/work" add file.txt
git -C "$d/work" diff --quiet HEAD; staged_rc=$?
git -C "$d/work" reset -q --hard HEAD

printf 'new\n' > "$d/work/untracked.txt"
git -C "$d/work" diff --quiet HEAD; untracked_rc=$?

printf 'run-edit\n' >> "$d/work/file.txt"
git -C "$d/work" commit -qa --amend --no-edit
# The one seed commit makes this amend rewrite the root, so `git show --stat` lists file.txt as
# added regardless of whether -a staged the append — assert the committed blob's content instead.
committed_content=$(git -C "$d/work" show HEAD:file.txt)
tracked_content_ok=0
printf '%s\n' "$committed_content" | $GREP -q 'run-edit' && tracked_content_ok=1
untracked_survives=0
[ -f "$d/work/untracked.txt" ] && untracked_survives=1
untracked_tracked=$(git -C "$d/work" ls-files untracked.txt | $GREP -c . || true)
if [ "$unstaged_rc" -ne 0 ] && [ "$staged_rc" -ne 0 ] && [ "$untracked_rc" -eq 0 ] \
   && [ "$tracked_content_ok" -eq 1 ] && [ "$untracked_survives" -eq 1 ] && [ "$untracked_tracked" -eq 0 ]; then
    pass "git diff --quiet HEAD fails on a staged or an unstaged tracked modification and passes with only an untracked file present, and git commit -a --amend stages the tracked modification's content without the untracked file"
else
    fail "git diff --quiet HEAD fails on a staged or an unstaged tracked modification and passes with only an untracked file present, and git commit -a --amend stages the tracked modification's content without the untracked file" \
         "unstaged_rc=$unstaged_rc staged_rc=$staged_rc untracked_rc=$untracked_rc committed_content=$committed_content untracked_survives=$untracked_survives untracked_tracked=$untracked_tracked"
fi

# 3 (M8): forcing the committer date forward is what manufactures the SHA difference here — a
# same-second amend returns an identical SHA, so this proves the mechanism, not an "always differs" claim.
d=$(new_repo unchanged_amend)
old_sha=$(git -C "$d/work" rev-parse HEAD)
GIT_COMMITTER_DATE='2030-01-01T00:00:00' git -C "$d/work" commit -qa --amend --no-edit
new_sha=$(git -C "$d/work" rev-parse HEAD)
push_out=$(git -C "$d/work" push --force origin source:source 2>&1); push_rc=$?
remote_sha=$(git -C "$d/origin" rev-parse refs/heads/source)
if [ "$old_sha" != "$new_sha" ] && [ "$push_rc" -eq 0 ] && [ "$remote_sha" = "$new_sha" ] \
   && printf '%s' "$push_out" | $GREP -qi 'forced update'; then
    pass "git commit -a --amend --no-edit over an unchanged tree exits 0, and with the committer date forced forward writes a differing SHA whose push reports a forced update"
else
    fail "git commit -a --amend --no-edit over an unchanged tree exits 0, and with the committer date forced forward writes a differing SHA whose push reports a forced update" \
         "old=$old_sha new=$new_sha push_rc=$push_rc remote=$remote_sha out=$push_out"
fi

# 4: a plain `git push` under `upstream` sends the branch to branch.source.merge, not
# refs/heads/source; under `matching` it sends every same-named local branch, not just this one.
d=$(new_repo push_default_upstream)
seed_sha=$(git -C "$d/work" rev-parse HEAD)
git -C "$d/work" config branch.source.remote origin
git -C "$d/work" config branch.source.merge refs/heads/other
git -C "$d/work" config push.default upstream
printf 'edit\n' >> "$d/work/file.txt"
git -C "$d/work" commit -qam edit
git -C "$d/work" push -q origin 2>/dev/null; push_rc=$?
source_after=$(git -C "$d/origin" rev-parse refs/heads/source)
# A bare `rev-parse` on an absent ref prints the refname to stdout, so `|| echo none` appends
# rather than replacing; `-q --verify` fixes that. The push's own exit status is checked too.
other_after=$(git -C "$d/origin" rev-parse -q --verify refs/heads/other 2>/dev/null || echo none)
upstream_ok=0
[ "$push_rc" -eq 0 ] && [ "$source_after" = "$seed_sha" ] && [ "$other_after" != "none" ] && upstream_ok=1

d=$(new_repo push_default_matching)
git -C "$d/work" branch feature-x
git -C "$d/work" push -q origin feature-x
git -C "$d/work" config push.default matching
printf 'edit-source\n' >> "$d/work/file.txt"
git -C "$d/work" commit -qam 'edit on source'
git -C "$d/work" checkout -q feature-x
printf 'edit-featurex\n' >> "$d/work/file.txt"
git -C "$d/work" commit -qam 'edit on feature-x'
git -C "$d/work" checkout -q source
git -C "$d/work" push -q origin 2>/dev/null
source_local=$(git -C "$d/work" rev-parse source)
featurex_local=$(git -C "$d/work" rev-parse feature-x)
source_remote=$(git -C "$d/origin" rev-parse refs/heads/source)
featurex_remote=$(git -C "$d/origin" rev-parse refs/heads/feature-x)
matching_ok=0
[ "$source_remote" = "$source_local" ] && [ "$featurex_remote" = "$featurex_local" ] && matching_ok=1

if [ "$upstream_ok" -eq 1 ] && [ "$matching_ok" -eq 1 ]; then
    pass "push.default=upstream sends the current branch to branch.source.merge rather than refs/heads/source, and push.default=matching sends every same-named local branch"
else
    fail "push.default=upstream sends the current branch to branch.source.merge rather than refs/heads/source, and push.default=matching sends every same-named local branch" \
         "upstream_ok=$upstream_ok matching_ok=$matching_ok"
fi

# 5: FR-7's positive control — the explicit refspec must touch only refs/heads/source; feature-y
# is advanced locally but not pushed, so a dropped refspec under matching would send it too.
for pd in upstream matching; do
    d=$(new_repo "explicit_refspec_$pd")
    git -C "$d/work" config branch.source.remote origin
    git -C "$d/work" config branch.source.merge refs/heads/other
    git -C "$d/work" config push.default "$pd"
    git -C "$d/work" branch feature-y
    git -C "$d/work" push -q origin feature-y
    git -C "$d/work" checkout -q feature-y
    printf 'feature-y edit\n' >> "$d/work/file.txt"
    git -C "$d/work" commit -qam 'advance feature-y locally, not yet pushed'
    git -C "$d/work" checkout -q source
    other_before=$(git -C "$d/origin" rev-parse -q --verify refs/heads/other 2>/dev/null || echo none)
    featurey_before=$(git -C "$d/origin" rev-parse refs/heads/feature-y)
    base=$(git -C "$d/work" rev-parse HEAD)
    printf 'edit\n' >> "$d/work/file.txt"
    git -C "$d/work" commit -qam edit
    git -C "$d/work" push -q --force-with-lease="source:$base" origin 'refs/heads/source:refs/heads/source'
    source_after=$(git -C "$d/origin" rev-parse refs/heads/source)
    other_after=$(git -C "$d/origin" rev-parse -q --verify refs/heads/other 2>/dev/null || echo none)
    featurey_after=$(git -C "$d/origin" rev-parse refs/heads/feature-y)
    source_local=$(git -C "$d/work" rev-parse source)
    if [ "$source_after" = "$source_local" ] && [ "$other_after" = "$other_before" ] && [ "$featurey_after" = "$featurey_before" ]; then
        pass "the push line's explicit refspec under push.default=$pd updates only refs/heads/source, leaving refs/heads/other and refs/heads/feature-y (advanced locally, not pushed) untouched"
    else
        fail "the push line's explicit refspec under push.default=$pd updates only refs/heads/source, leaving refs/heads/other and refs/heads/feature-y untouched" \
             "source_after=$source_after(local=$source_local) other_after=$other_after(before=$other_before) featurey_after=$featurey_after(before=$featurey_before)"
    fi
done

# 6: the pinned base SHA — an explicit-value lease rejects against a stale base once a second
# clone has pushed; an implicit lease, taken after a fetch refreshes the tracking ref, succeeds.
d="$TMPDIR_ROOT/lease"
mkdir -p "$d"
git init --bare -q "$d/origin"
git clone -q "$d/origin" "$d/clone1" 2>/dev/null
git -C "$d/clone1" checkout -q -b source
git -C "$d/clone1" config user.email a@example.com
git -C "$d/clone1" config user.name A
printf 'seed\n' > "$d/clone1/file.txt"
git -C "$d/clone1" add file.txt
git -C "$d/clone1" commit -q -m seed
git -C "$d/clone1" push -q origin source:refs/heads/source
git clone -q "$d/origin" "$d/clone2" 2>/dev/null
git -C "$d/clone2" config user.email b@example.com
git -C "$d/clone2" config user.name B
git -C "$d/clone2" checkout -q source
stale_base=$(git -C "$d/clone1" rev-parse HEAD)
printf 'clone2 edit\n' >> "$d/clone2/file.txt"
git -C "$d/clone2" commit -qam 'clone2 edit'
git -C "$d/clone2" push -q origin source
clone2_sha=$(git -C "$d/clone2" rev-parse HEAD)
printf 'clone1 edit\n' >> "$d/clone1/file.txt"
git -C "$d/clone1" commit -qam 'clone1 edit'
git -C "$d/clone1" push --force-with-lease="source:$stale_base" origin source >/dev/null 2>&1
explicit_rc=$?
remote_after_reject=$(git -C "$d/origin" rev-parse refs/heads/source)
git -C "$d/clone1" fetch -q origin
git -C "$d/clone1" push --force-with-lease=source origin source >/dev/null 2>&1
implicit_rc=$?
remote_after_implicit=$(git -C "$d/origin" rev-parse refs/heads/source)
clone1_sha=$(git -C "$d/clone1" rev-parse HEAD)
if [ "$explicit_rc" -ne 0 ] && [ "$remote_after_reject" = "$clone2_sha" ] \
   && [ "$implicit_rc" -eq 0 ] && [ "$remote_after_implicit" = "$clone1_sha" ] \
   && [ "$remote_after_implicit" != "$clone2_sha" ]; then
    pass "an explicit-value lease rejects against a stale base after a second clone's push, and an implicit lease taken after an intervening fetch succeeds and overwrites that clone's commit"
else
    fail "an explicit-value lease rejects against a stale base after a second clone's push, and an implicit lease taken after an intervening fetch succeeds and overwrites that clone's commit" \
         "explicit_rc=$explicit_rc reject_remote=$remote_after_reject(want $clone2_sha) implicit_rc=$implicit_rc implicit_remote=$remote_after_implicit(want $clone1_sha)"
fi

# 7: the `not acted on` arm for a protected branch — a remote pre-receive hook that exits
# non-zero rejects the push, and the exit-status check fires.
d=$(new_repo hook_reject)
cat > "$d/origin/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "rejected by policy" >&2
exit 1
HOOK
chmod +x "$d/origin/hooks/pre-receive"
printf 'edit\n' >> "$d/work/file.txt"
git -C "$d/work" commit -qam edit
push_err=$(git -C "$d/work" push origin source 2>&1); push_rc=$?
if [ "$push_rc" -ne 0 ] && printf '%s' "$push_err" | $GREP -qi 'rejected by policy'; then
    pass "a remote pre-receive hook that exits non-zero rejects the push, and the exit-status check fires"
else
    fail "a remote pre-receive hook that exits non-zero rejects the push, and the exit-status check fires" \
         "push_rc=$push_rc err=$push_err"
fi

# 8: the re-check's tree half — it flags a tracked modification outside the recorded set,
# and passes when the modified and recorded sets match exactly.
d=$(new_repo recheck_paths)
printf 'a\n' > "$d/work/other.txt"
git -C "$d/work" add other.txt
git -C "$d/work" commit -qm 'seed other'
printf 'x\n' >> "$d/work/file.txt"
printf 'y\n' >> "$d/work/other.txt"
recheck_tree "$d/work" "file.txt"; outside_rc=$?
git -C "$d/work" checkout -q -- file.txt other.txt
printf 'x\n' >> "$d/work/file.txt"
recheck_tree "$d/work" "file.txt"; matched_rc=$?
if [ "$outside_rc" -ne 0 ] && [ "$matched_rc" -eq 0 ]; then
    pass "the re-check flags a tracked modification outside the recorded path set, and passes when the modified and recorded sets match"
else
    fail "the re-check flags a tracked modification outside the recorded path set, and passes when the modified and recorded sets match" \
         "outside_rc=$outside_rc matched_rc=$matched_rc"
fi

# 9: the re-check's HEAD half — the tree comparison alone passes vacuously once a commit lands
# in the fixing window and the tree reads clean; HEAD equality is what actually fires.
d=$(new_repo recheck_head)
base_sha=$(git -C "$d/work" rev-parse HEAD)
printf 'intervening\n' >> "$d/work/file.txt"
git -C "$d/work" commit -qam 'intervening commit, not the runs own edit'
recheck_tree "$d/work" ""; tree_rc=$?
head_now=$(git -C "$d/work" rev-parse HEAD)
if [ "$tree_rc" -eq 0 ] && [ "$head_now" != "$base_sha" ]; then
    pass "the tree half of the re-check passes vacuously once a commit lands in the fixing window and the tree reads clean; HEAD equality against the guarded base SHA is what fires"
else
    fail "the tree half of the re-check passes vacuously once a commit lands in the fixing window and the tree reads clean; HEAD equality against the guarded base SHA is what fires" \
         "tree_rc=$tree_rc base_sha=$base_sha head_now=$head_now"
fi

# 10: the restore rule and its shared-path stop (M5) — ownership comes from fix_owner_of, not a
# hardcoded outcome; H6: a created path (absent from the guarded tip) restores via rm -f.
d=$(new_repo restore_rule)
printf 'b\n' > "$d/work/precond.txt"
git -C "$d/work" add precond.txt
git -C "$d/work" commit -qm 'seed precond'
printf 'c\n' > "$d/work/shared_fix.txt"
git -C "$d/work" add shared_fix.txt
git -C "$d/work" commit -qm 'seed shared-fix path, already completed by ordinal 2'
orig_file=$(cat "$d/work/file.txt")
orig_precond=$(cat "$d/work/precond.txt")
completed_content=$(cat "$d/work/shared_fix.txt")

# fix_owner_of: the mark 5c records — which ordinal, if any, recorded this path as its fix's.
fix_owner_of() {
    case "$1" in
        file.txt) echo 1 ;;
        shared_fix.txt) echo 2 ;;
        *) echo '' ;;
    esac
}

# restore_row: restores every path (space-separated) ordinal $1 recorded, skipping one another
# ordinal's fix also recorded (the collision that stops the run before the git leg, named in
# its return value), and restoring a path absent from the guarded tip with rm -f, not checkout.
restore_row() {
    local ordinal="$1" repo="$2" paths="$3" path owner collided=""
    for path in $paths; do
        owner=$(fix_owner_of "$path")
        if [ -n "$owner" ] && [ "$owner" != "$ordinal" ]; then
            collided="${collided}${path}(owned by ${owner}); "
            continue
        fi
        if git -C "$repo" cat-file -e "HEAD:$path" 2>/dev/null; then
            git -C "$repo" checkout -q -- "$path"
        else
            rm -f -- "$repo/$path"
        fi
    done
    printf '%s' "$collided"
}

printf 'row-a-edit\n' >> "$d/work/file.txt"
printf 'precond-scratch\n' >> "$d/work/precond.txt"
printf 'row-a-touched-by-mistake\n' >> "$d/work/shared_fix.txt"
printf 'new-untracked\n' > "$d/work/created_by_row_a.txt"
collision_report=$(restore_row 1 "$d/work" "file.txt precond.txt shared_fix.txt created_by_row_a.txt")

# A collision must stop the run before the git leg — restore_row's own return value only names
# the shared path; nothing modelled that every OTHER approved row takes not acted on and that no
# git-leg command runs. A row with no collision of its own is not exempt: a stop is whole-run,
# per design §5.3's "every other approved row takes not acted on".
other_row_end_state="reply issued"
git_leg_would_run=1
if [ -n "$collision_report" ]; then
    other_row_end_state="not acted on"
    git_leg_would_run=0
fi

if [ "$(cat "$d/work/file.txt")" = "$orig_file" ] \
   && [ "$(cat "$d/work/precond.txt")" = "$orig_precond" ] \
   && [ "$(cat "$d/work/shared_fix.txt")" != "$completed_content" ] \
   && [ ! -e "$d/work/created_by_row_a.txt" ] \
   && printf '%s' "$collision_report" | $GREP -qF 'shared_fix.txt(owned by 2)' \
   && [ "$other_row_end_state" = "not acted on" ] \
   && [ "$git_leg_would_run" -eq 0 ]; then
    pass "a row restoring its recorded paths returns a tracked path and a shared preconditions path to pre-run content, removes a path it created, skips a path another row's fix also recorded, names that collision, and stops the run before the git leg with every other approved row taking not acted on"
else
    fail "a row restoring its recorded paths returns a tracked path and a shared preconditions path to pre-run content, removes a path it created, skips a path another row's fix also recorded, names that collision, and stops the run before the git leg with every other approved row taking not acted on" \
         "file=$(cat "$d/work/file.txt") precond=$(cat "$d/work/precond.txt") shared=$(cat "$d/work/shared_fix.txt") created_exists=$([ -e "$d/work/created_by_row_a.txt" ] && echo yes || echo no) collision_report=$collision_report other_row_end_state=$other_row_end_state git_leg_would_run=$git_leg_would_run"
fi

echo "== Predicate: the resolve-set construction =="

# projctl stand-in on PATH — `load mr` cats a fixture JSON file named by
# $PROJCTL_LOAD_FIXTURE; `comment` appends the file argument it was given to
# $PROJCTL_COMMENT_LOG. Neither touches a real GitLab.
PROJCTL_STUB_DIR="$TMPDIR_ROOT/stub-bin"
mkdir -p "$PROJCTL_STUB_DIR"
cat > "$PROJCTL_STUB_DIR/projctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    load)
        cat "${PROJCTL_LOAD_FIXTURE:?PROJCTL_LOAD_FIXTURE not set}"
        ;;
    comment)
        printf '%s\n' "$2" >> "${PROJCTL_COMMENT_LOG:?PROJCTL_COMMENT_LOG not set}"
        ;;
    *)
        echo "unsupported stub command: $*" >&2
        exit 1
        ;;
esac
STUB
chmod +x "$PROJCTL_STUB_DIR/projctl"

# fixmr_build_resolve_set: a stand-in for the resolve-set construction — the predicate and
# the refusal ahead of it, not the run's own orchestration, which nothing here executes.
#
# $1 batch mr_number, $2 invocation mr_number, $3 admitted-rows fixture
#    (discussion_id|thread_action|resolvable|expected_reply, one per line), $4 output path for
#    the discussion_ids the predicate admits to the resolve set.
# Prints "<discussion_id> <label>" per admitted row to stdout. Calls the `projctl` stand-in on
# PATH exactly once (`load mr`) when the mr_number matches, and never when it does not.
fixmr_build_resolve_set() {
    local batch_mr="$1" invocation_mr="$2" rows_file="$3" resolve_out="$4"
    : > "$resolve_out"
    if [ "$batch_mr" != "$invocation_mr" ]; then
        echo "REFUSED: batch mr_number ($batch_mr) != invocation mr_number ($invocation_mr)"
        return 1
    fi
    local reread
    reread=$(projctl load mr "$invocation_mr" --comments --json) || { echo "LOAD_FAILED"; return 1; }
    printf '%s' "$reread" > "$TMPDIR_ROOT/.reread.json"
    python3 - "$rows_file" "$TMPDIR_ROOT/.reread.json" "$resolve_out" <<'PYEOF'
import json
import sys

rows_path, reread_path, resolve_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(reread_path, encoding="utf-8") as f:
    data = json.load(f)
threads = {t["discussion_id"]: t for t in data.get("threads", [])}

# 6c's three-key floor is checked over the WHOLE re-read before any row is admitted — fix-mr.md
# says "Refuse the posting pass", a whole-pass refusal, not a per-thread skip. Checking here,
# ahead of the rows loop, means an otherwise-valid thread earlier in rows_file is never written
# to resolve_path either, regardless of row order — a per-row `continue` would have already
# admitted it before reaching the bad record.
for discussion_id, thread in threads.items():
    if "notes" not in thread or "resolved" not in thread:
        print(f"{discussion_id} FLOOR_FAILED")
        sys.exit(1)

with open(rows_path, encoding="utf-8") as f, open(resolve_path, "w", encoding="utf-8") as out:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        discussion_id, thread_action, resolvable, expected_reply = line.split("|", 3)
        thread = threads.get(discussion_id)
        if thread is None:
            print(f"{discussion_id} MISSING")
            continue
        if thread_action != "resolved":
            print(f"{discussion_id} answered")  # left open: no resolve is owed
            continue
        if resolvable != "true":
            print(f"{discussion_id} answered")  # resolvable false: answered, thread left open
            continue
        bodies = [n.get("body", "").strip() for n in thread.get("notes", [])]
        if expected_reply not in bodies:
            print(f"{discussion_id} reply_missing")
            continue
        if thread["resolved"]:
            print(f"{discussion_id} answered")  # already resolved: no call needed for it
            continue
        print(f"{discussion_id} answered")
        out.write(discussion_id + "\n")
PYEOF
}

REPLY_BODY='The claim holds; X breaks. Fixed in a1b2c3d.'

# 11: every conjunct holds — the discussion_id reaches the resolve YAML, and the row is
# recorded answered.
fixture="$TMPDIR_ROOT/f11.json"
rows="$TMPDIR_ROOT/r11.txt"
resolve_out="$TMPDIR_ROOT/resolve11.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d11", "resolved": false, "notes": [{"body": "$REPLY_BODY"}]}]}
EOF
printf 'd11|resolved|true|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log11.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd11 answered' && $GREP -qF d11 "$resolve_out"; then
    pass "every conjunct holds: the discussion_id reaches the resolve YAML and the row records answered"
else
    fail "every conjunct holds: the discussion_id reaches the resolve YAML and the row records answered" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

# 12: the reply body is absent from the thread's notes — omitted from the resolve set, and the
# row records reply missing.
fixture="$TMPDIR_ROOT/f12.json"
rows="$TMPDIR_ROOT/r12.txt"
resolve_out="$TMPDIR_ROOT/resolve12.txt"
cat > "$fixture" <<'EOF'
{"threads": [{"discussion_id": "d12", "resolved": false, "notes": [{"body": "unrelated note"}]}]}
EOF
printf 'd12|resolved|true|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log12.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd12 reply_missing' && ! $GREP -qF d12 "$resolve_out"; then
    pass "the reply body is absent from the thread's notes: omitted from the resolve set, and the row records reply missing"
else
    fail "the reply body is absent from the thread's notes: omitted from the resolve set, and the row records reply missing" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

# 13: resolvable is false — omitted from the resolve set, and the row records answered with
# the thread left open.
fixture="$TMPDIR_ROOT/f13.json"
rows="$TMPDIR_ROOT/r13.txt"
resolve_out="$TMPDIR_ROOT/resolve13.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d13", "resolved": false, "notes": [{"body": "$REPLY_BODY"}]}]}
EOF
printf 'd13|resolved|false|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log13.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd13 answered' && ! $GREP -qF d13 "$resolve_out"; then
    pass "resolvable is false: omitted from the resolve set, and the row records answered with the thread left open"
else
    fail "resolvable is false: omitted from the resolve set, and the row records answered with the thread left open" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

# 14: thread_action is left open — no resolve is owed at all, so the row is never even weighed
# against the re-read.
fixture="$TMPDIR_ROOT/f14.json"
rows="$TMPDIR_ROOT/r14.txt"
resolve_out="$TMPDIR_ROOT/resolve14.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d14", "resolved": false, "notes": [{"body": "$REPLY_BODY"}]}]}
EOF
printf 'd14|left open|true|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log14.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd14 answered' && ! $GREP -qF d14 "$resolve_out"; then
    pass "thread_action is left open: no resolve is owed, and the row is omitted from the resolve set"
else
    fail "thread_action is left open: no resolve is owed, and the row is omitted from the resolve set" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

# 15: the read already shows the thread resolved — omitted, and no call is made for it.
fixture="$TMPDIR_ROOT/f15.json"
rows="$TMPDIR_ROOT/r15.txt"
resolve_out="$TMPDIR_ROOT/resolve15.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d15", "resolved": true, "notes": [{"body": "$REPLY_BODY"}]}]}
EOF
printf 'd15|resolved|true|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log15.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd15 answered' && ! $GREP -qF d15 "$resolve_out"; then
    pass "the read already shows the thread resolved: omitted from the resolve set, and no resolve call is owed for it"
else
    fail "the read already shows the thread resolved: omitted from the resolve set, and no resolve call is owed for it" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

# 16: the batch's mr_number differs from the invocation's — refuse before any stand-in call.
# PROJCTL_LOAD_FIXTURE stays unset so the stub itself aborts loudly if ever invoked.
rows="$TMPDIR_ROOT/r16.txt"
resolve_out="$TMPDIR_ROOT/resolve16.txt"
comment_log="$TMPDIR_ROOT/log16.txt"
printf 'd16|resolved|true|%s\n' "$REPLY_BODY" > "$rows"
unset PROJCTL_LOAD_FIXTURE
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_COMMENT_LOG="$comment_log" \
      fixmr_build_resolve_set 280 281 "$rows" "$resolve_out"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | $GREP -qF 'REFUSED' \
   && [ ! -s "$resolve_out" ] && [ ! -e "$comment_log" ]; then
    pass "a batch mr_number differing from the invocation's refuses before the stand-in receives any call and before any git command"
else
    fail "a batch mr_number differing from the invocation's refuses before the stand-in receives any call and before any git command" \
         "rc=$rc out=$out resolve_out_exists=$([ -e "$resolve_out" ] && echo yes || echo no) comment_log_exists=$([ -e "$comment_log" ] && echo yes || echo no)"
fi

# 17: 6c's three-key floor — a thread record missing `resolved` entirely must refuse the whole
# posting pass, not skip past that one thread. A single-thread fixture cannot tell "skip this
# row" from "refuse the pass" apart, since both leave a one-row resolve set empty either way —
# d17_ok is a second, otherwise-admissible thread that a per-thread `continue` would already
# have written to resolve_out before ever reaching d17's bad record; asserting it is absent too
# is what proves the whole pass refused rather than one row being skipped.
fixture="$TMPDIR_ROOT/f17.json"
rows="$TMPDIR_ROOT/r17.txt"
resolve_out="$TMPDIR_ROOT/resolve17.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d17_ok", "resolved": false, "notes": [{"body": "$REPLY_BODY"}]}, {"discussion_id": "d17", "notes": [{"body": "$REPLY_BODY"}]}]}
EOF
{
    printf 'd17_ok|resolved|true|%s\n' "$REPLY_BODY"
    printf 'd17|resolved|true|%s\n' "$REPLY_BODY"
} > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log17.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out"); rc17=$?
if [ "$rc17" -ne 0 ] && printf '%s\n' "$out" | $GREP -qF 'd17 FLOOR_FAILED' \
   && ! printf '%s\n' "$out" | $GREP -qF 'd17_ok answered' \
   && [ ! -s "$resolve_out" ]; then
    pass "a thread record missing the resolved key refuses the whole posting pass — a second, otherwise-admissible thread is never admitted either"
else
    fail "a thread record missing the resolved key refuses the whole posting pass — a second, otherwise-admissible thread is never admitted either" \
         "rc17=$rc17 out=$out resolve_out=$(cat "$resolve_out" 2>/dev/null)"
fi

# 18: membership beats last-note position — the reply is present but not the thread's last
# note; a third party's comment landing after it must not stop the reply from being found.
fixture="$TMPDIR_ROOT/f18.json"
rows="$TMPDIR_ROOT/r18.txt"
resolve_out="$TMPDIR_ROOT/resolve18.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d18", "resolved": false, "notes": [{"body": "$REPLY_BODY"}, {"body": "a third party comment landing after the reply"}]}]}
EOF
printf 'd18|resolved|true|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log18.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd18 answered' && $GREP -qF d18 "$resolve_out"; then
    pass "membership beats last-note position: the reply is found though a third party's note landed after it"
else
    fail "membership beats last-note position: the reply is found though a third party's note landed after it" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

# 19: the MISSING branch — a discussion_id absent from the re-read's thread set, alongside an
# unrelated present thread, so the lookup is a real dict membership test, not a single-entry one.
fixture="$TMPDIR_ROOT/f19.json"
rows="$TMPDIR_ROOT/r19.txt"
resolve_out="$TMPDIR_ROOT/resolve19.txt"
cat > "$fixture" <<EOF
{"threads": [{"discussion_id": "d19_present", "resolved": false, "notes": [{"body": "$REPLY_BODY"}]}]}
EOF
printf 'd19_absent|resolved|true|%s\n' "$REPLY_BODY" > "$rows"
out=$(PATH="$PROJCTL_STUB_DIR:$PATH" PROJCTL_LOAD_FIXTURE="$fixture" PROJCTL_COMMENT_LOG="$TMPDIR_ROOT/log19.txt" \
      fixmr_build_resolve_set 280 280 "$rows" "$resolve_out")
if printf '%s\n' "$out" | $GREP -qF 'd19_absent MISSING' && ! $GREP -qF d19_absent "$resolve_out"; then
    pass "a discussion_id absent from the re-read's thread set is reported MISSING and omitted from the resolve set"
else
    fail "a discussion_id absent from the re-read's thread set is reported MISSING and omitted from the resolve set" \
         "out=$out resolve_out=$(cat "$resolve_out")"
fi

echo "== Predicate: the batch-level refusals (Step 5a) =="

# fixmr_validate_batch: a stand-in for Step 5a's four batch-level refusals — the file is absent
# or does not parse, mr_number differs from the invocation's, no row carries approved: true, or
# an approved row's verdict/disposition/thread_action falls outside its own vocabulary. A
# declined (by-design/refuted) row's disposition is null by design (Step 2a's schema) and must
# not itself trip the vocabulary check (M12) — only a non-null, non-fix/propose value should.
#
# $1 batch file path (may be absent), $2 invocation mr_number. Prints "REFUSED: <reason>" and
# returns 1 on any refusal; prints "OK" and returns 0 otherwise.
fixmr_validate_batch() {
    local batch_file="$1" invocation_mr="$2"
    if [ ! -f "$batch_file" ]; then
        echo "REFUSED: batch file absent"
        return 1
    fi
    python3 - "$batch_file" "$invocation_mr" <<'PYEOF'
import sys
import yaml

batch_file, invocation_mr = sys.argv[1], sys.argv[2]
try:
    with open(batch_file, encoding="utf-8") as f:
        data = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f"REFUSED: batch file does not parse: {e}")
    sys.exit(1)

if not isinstance(data, dict):
    print("REFUSED: batch file does not parse: top level is not a mapping")
    sys.exit(1)

if str(data.get("mr_number")) != str(invocation_mr):
    print(f"REFUSED: mr_number ({data.get('mr_number')}) != invocation mr_number ({invocation_mr})")
    sys.exit(1)

approved = [t for t in (data.get("threads") or []) if t.get("approved") is True]
if not approved:
    print("REFUSED: no row carries approved: true")
    sys.exit(1)

verdict_vocab = {"real", "by-design", "refuted"}
thread_action_vocab = {"resolved", "left open"}
for t in approved:
    verdict = t.get("verdict")
    disposition = t.get("disposition")
    thread_action = t.get("thread_action")
    if verdict not in verdict_vocab:
        print(f"REFUSED: row {t.get('ordinal')}'s verdict '{verdict}' outside its vocabulary")
        sys.exit(1)
    if thread_action not in thread_action_vocab:
        print(f"REFUSED: row {t.get('ordinal')}'s thread_action '{thread_action}' outside its vocabulary")
        sys.exit(1)
    if verdict == "real":
        if disposition not in ("fix", "propose"):
            print(f"REFUSED: row {t.get('ordinal')}'s disposition '{disposition}' outside its vocabulary")
            sys.exit(1)
    elif disposition is not None:
        print(f"REFUSED: row {t.get('ordinal')}'s disposition '{disposition}' outside its vocabulary")
        sys.exit(1)

print("OK")
PYEOF
}

# 20: the file is absent, or present but not valid YAML — both refuse by name, before any row
# is examined.
out=$(fixmr_validate_batch "$TMPDIR_ROOT/no-such-batch.yaml" 280); rc_absent=$?
bad_yaml="$TMPDIR_ROOT/bad-batch.yaml"
printf 'mr_number: 280\nthreads: [unterminated\n' > "$bad_yaml"
out_bad=$(fixmr_validate_batch "$bad_yaml" 280); rc_bad=$?
if [ "$rc_absent" -ne 0 ] && printf '%s' "$out" | $GREP -qF 'REFUSED: batch file absent' \
   && [ "$rc_bad" -ne 0 ] && printf '%s' "$out_bad" | $GREP -qF 'REFUSED: batch file does not parse'; then
    pass "an absent batch file and a malformed one each refuse by name, before any row is examined"
else
    fail "an absent batch file and a malformed one each refuse by name, before any row is examined" \
         "rc_absent=$rc_absent out=$out rc_bad=$rc_bad out_bad=$out_bad"
fi

# 21: a batch with rows but none carrying approved: true refuses by name.
no_approved="$TMPDIR_ROOT/no-approved-batch.yaml"
cat > "$no_approved" <<'EOF'
mr_number: 280
threads:
  - ordinal: 1
    approved: false
    verdict: real
EOF
out=$(fixmr_validate_batch "$no_approved" 280); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | $GREP -qF 'REFUSED: no row carries approved: true'; then
    pass "a batch with no row carrying approved: true refuses by name"
else
    fail "a batch with no row carrying approved: true refuses by name" "rc=$rc out=$out"
fi

# 22: the vocabulary check refuses on a genuine violation, and does NOT refuse a declined row's
# disposition: null (M12) — both directions, since strict-enough and loose-enough are the point.
bad_verdict="$TMPDIR_ROOT/bad-verdict-batch.yaml"
cat > "$bad_verdict" <<'EOF'
mr_number: 280
threads:
  - ordinal: 1
    approved: true
    verdict: not-a-real-verdict
    disposition: null
    thread_action: resolved
EOF
out_bad=$(fixmr_validate_batch "$bad_verdict" 280); rc_bad=$?
declined_null_disp="$TMPDIR_ROOT/declined-null-disposition-batch.yaml"
cat > "$declined_null_disp" <<'EOF'
mr_number: 280
threads:
  - ordinal: 2
    approved: true
    verdict: by-design
    disposition: null
    thread_action: resolved
EOF
out_ok=$(fixmr_validate_batch "$declined_null_disp" 280); rc_ok=$?
if [ "$rc_bad" -ne 0 ] && printf '%s' "$out_bad" | $GREP -qF "verdict 'not-a-real-verdict' outside its vocabulary" \
   && [ "$rc_ok" -eq 0 ] && printf '%s' "$out_ok" | $GREP -qF 'OK'; then
    pass "an out-of-vocabulary verdict refuses by name, and a declined row's disposition: null does not (M12)"
else
    fail "an out-of-vocabulary verdict refuses by name, and a declined row's disposition: null does not (M12)" \
         "rc_bad=$rc_bad out_bad=$out_bad rc_ok=$rc_ok out_ok=$out_ok"
fi

echo "== Unit: 5d's ledger write =="

# fixmr_ledger_write: a stand-in for 5d's ledger write — appends an entry naming its
# discussion_id in regression-test/SKILL.md's format after the push succeeds, and replaces an
# existing entry naming this discussion_id rather than duplicating it (one failure, one entry).
#
# $1 ledger file, $2 discussion_id, $3 status (covered|out-of-scope), $4 detail (Test: path for
# covered, Reason: clause for out-of-scope).
fixmr_ledger_write() {
    local ledger="$1" discussion_id="$2" status="$3" detail="$4" kept
    kept=$(mktemp -p "$TMPDIR_ROOT")
    if [ -f "$ledger" ]; then
        awk -v marker="(discussion_id $discussion_id)" '
          /^## / { skip = (index($0, marker) > 0) }
          !skip { print }
        ' "$ledger" > "$kept"
    fi
    {
        cat "$kept"
        echo "## fix landed (discussion_id $discussion_id)"
        echo
        echo "**Status:** $status"
        if [ "$status" = covered ]; then
            echo "**Test:** \`$detail\`"
            echo "**Evidence:** before fix FAIL; after fix PASS"
        else
            echo "**Reason:** $detail"
        fi
        echo
    } > "$ledger.new"
    mv "$ledger.new" "$ledger"
    rm -f "$kept"
}

# 23: both Status shapes, and the replace-by-discussion_id rule — a second write for the same
# discussion_id replaces its entry rather than duplicating it, leaving a different one untouched.
ledger="$TMPDIR_ROOT/observed-failures.md"
fixmr_ledger_write "$ledger" d23a covered 'tests/integration/test_x.py::test_y'
fixmr_ledger_write "$ledger" d23b out-of-scope 'no repository component — runner offline'
fixmr_ledger_write "$ledger" d23a covered 'tests/integration/test_x.py::test_y_v2'
n_d23a=$($GREP -cF 'discussion_id d23a' "$ledger" || true)
n_d23b=$($GREP -cF 'discussion_id d23b' "$ledger" || true)
if [ "$n_d23a" -eq 1 ] && [ "$n_d23b" -eq 1 ] \
   && $GREP -qF 'test_y_v2' "$ledger" \
   && $GREP -qF '**Status:** out-of-scope' "$ledger" && $GREP -qF 'no repository component' "$ledger"; then
    pass "a second ledger write for the same discussion_id replaces its entry rather than duplicating it, leaving a different discussion_id's entry untouched"
else
    fail "a second ledger write for the same discussion_id replaces its entry rather than duplicating it, leaving a different discussion_id's entry untouched" \
         "n_d23a=$n_d23a n_d23b=$n_d23b ledger=$(cat "$ledger")"
fi

echo
total=$((PASS + FAIL))
if [ "$total" -eq "$EXPECTED_TESTS" ]; then
    pass "all $EXPECTED_TESTS assertions ran"
else
    fail "all $EXPECTED_TESTS assertions ran" "ran $total — a block skipped itself or EXPECTED_TESTS is stale"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
