#!/usr/bin/env bash
# verify-workflow-safety.sh — gate-primitive regression tests for the workflow-safety milestone.
#
# Exercises the disk-checkable gate conditions defined in design §12.1 without invoking
# Claude Code. Uses a temporary directory for all fixtures; cleans up on exit.
#
# Exit codes: 0 = all tests passed, 1 = one or more tests failed.

set -euo pipefail

# Use /usr/bin/grep directly to avoid ugrep alias issues with POSIX character escaping.
GREP=/usr/bin/grep

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TMPDIR_ROOT=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

# Run a test: assert the given command exits 0.
assert_pass() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label (expected success, got failure)"
    fi
}

# Run a test: assert the given command exits non-zero.
assert_fail() {
    local label="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label (expected failure, got success)"
    fi
}

# The grep pattern the gates use, applied to a file: finds the status line.
marker_grep() {
    local file="$1"
    head -20 "$file" | $GREP -m 1 '^\*\*Status:\*\*'
}

# Extract just the state value after "**Status:** "
marker_state() {
    local file="$1"
    marker_grep "$file" | sed 's/\*\*Status:\*\* //'
}

# Check if a marker state is canonical (one of APPROVED, CHANGES REQUESTED, REJECTED).
is_canonical_state() {
    local state="$1"
    case "$state" in
        APPROVED|"CHANGES REQUESTED"|REJECTED) return 0 ;;
        *) return 1 ;;
    esac
}

# Check gate: marker exists AND state is canonical.
marker_gate_pass() {
    local file="$1"
    marker_grep "$file" >/dev/null 2>&1 || return 1
    local state
    state=$(marker_state "$file")
    is_canonical_state "$state"
}

# ---------------------------------------------------------------------------
# Section 1: Marker grep — canonical states and pre-convention files
# ---------------------------------------------------------------------------
echo ""
echo "=== 1. Marker grep: canonical states ==="

T="$TMPDIR_ROOT/marker_grep"
mkdir -p "$T"

# APPROVED fixture
cat >"$T/approved.md" <<'EOF'
# Review Summary

**Status:** APPROVED

Some content here.
EOF
assert_pass "APPROVED: marker line found" marker_grep "$T/approved.md"
RESULT=$(marker_state "$T/approved.md")
[ "$RESULT" = "APPROVED" ] && pass "APPROVED state is exactly 'APPROVED'" || fail "APPROVED state mismatch: got '$RESULT'"
assert_pass "APPROVED: gate passes" marker_gate_pass "$T/approved.md"

# CHANGES REQUESTED fixture
cat >"$T/changes_requested.md" <<'EOF'
# Review Summary

**Status:** CHANGES REQUESTED

Some content.
EOF
assert_pass "CHANGES REQUESTED: marker line found" marker_grep "$T/changes_requested.md"
RESULT=$(marker_state "$T/changes_requested.md")
[ "$RESULT" = "CHANGES REQUESTED" ] && pass "CHANGES REQUESTED state exact" || fail "CHANGES REQUESTED state mismatch: got '$RESULT'"
assert_pass "CHANGES REQUESTED: gate passes (state is canonical)" marker_gate_pass "$T/changes_requested.md"

# REJECTED fixture (N3 from review-v2)
cat >"$T/rejected.md" <<'EOF'
# Review Summary

**Status:** REJECTED

Some content.
EOF
assert_pass "REJECTED: marker line found" marker_grep "$T/rejected.md"
RESULT=$(marker_state "$T/rejected.md")
[ "$RESULT" = "REJECTED" ] && pass "REJECTED state exact" || fail "REJECTED state mismatch: got '$RESULT'"
assert_pass "REJECTED: gate passes (state is canonical)" marker_gate_pass "$T/rejected.md"

# Pre-convention file — marker line IS found (it starts with **Status:**) but
# the state value is not canonical (contains emoji and words), so the full gate fails.
# This is how the gate actually works: the grep finds the line; then the state check
# rejects non-canonical values. A pre-convention file fails the state check.
cat >"$T/pre_convention.md" <<'EOF'
# Review Summary

**Status:** ✅ Approved - Ready for Implementation

Some content.
EOF
# The raw grep finds the line (the pattern only checks the prefix)
assert_pass "Pre-convention: raw grep finds marker line (prefix matches)" marker_grep "$T/pre_convention.md"
# But the full gate must fail because the state is not canonical
assert_fail "Pre-convention: full gate fails (state is not canonical)" marker_gate_pass "$T/pre_convention.md"

# No status marker at all
cat >"$T/no_marker.md" <<'EOF'
# Review Summary

Some content without any status.
EOF
assert_fail "No marker: raw grep returns nothing" marker_grep "$T/no_marker.md"
assert_fail "No marker: full gate fails" marker_gate_pass "$T/no_marker.md"

# ---------------------------------------------------------------------------
# Section 2: Marker location — within first 20 lines
# ---------------------------------------------------------------------------
echo ""
echo "=== 2. Marker location: within first 20 lines ==="

T="$TMPDIR_ROOT/marker_location"
mkdir -p "$T"

# Marker on line 2 (immediately after H1, no blank line)
{
    printf "# Review Summary\n"
    printf "**Status:** APPROVED\n"
} >"$T/line2.md"
assert_pass "Marker on line 2 found" marker_grep "$T/line2.md"

# Marker on line 20
{
    printf "# Review Summary\n"
    for i in $(seq 1 18); do printf "line %d\n" "$i"; done
    printf "**Status:** APPROVED\n"
} >"$T/line20.md"
LINE_COUNT=$(wc -l <"$T/line20.md")
[ "$LINE_COUNT" -eq 20 ] && pass "line20.md has exactly 20 lines" || fail "line20.md has $LINE_COUNT lines (expected 20)"
assert_pass "Marker on line 20 found" marker_grep "$T/line20.md"

# Marker on line 21 — must NOT be found by head -20
{
    printf "# Review Summary\n"
    for i in $(seq 1 19); do printf "line %d\n" "$i"; done
    printf "**Status:** APPROVED\n"
} >"$T/line21.md"
assert_fail "Marker on line 21 not found (beyond head -20)" marker_grep "$T/line21.md"

# ---------------------------------------------------------------------------
# Section 3: /implement precondition 1
# ---------------------------------------------------------------------------
echo ""
echo "=== 3. /implement precondition 1 (design + review exist, mtime-ordered, APPROVED) ==="

T="$TMPDIR_ROOT/precond1"
mkdir -p "$T/planning/milestone/design" "$T/planning/milestone/reviews"

DESIGN="$T/planning/milestone/design/feature-design.md"
REVIEW="$T/planning/milestone/reviews/feature-design-review.md"

# Helper: check precondition 1
check_precond1() {
    local design="$1"
    local review="$2"
    # a) design exists
    test -f "$design" || return 1
    # b) review exists
    test -f "$review" || return 1
    # c) review mtime >= design mtime
    test "$review" -nt "$design" || test "$review" -ef "$design" || return 1
    # d) APPROVED marker (canonical check: line found AND state is APPROVED)
    local state
    state=$(head -20 "$review" | $GREP -m 1 '^\*\*Status:\*\*' | sed 's/\*\*Status:\*\* //') 2>/dev/null || return 1
    [ "$state" = "APPROVED" ] || return 1
    return 0
}

# Sub-case: design missing
assert_fail "precond1: design missing → fail" check_precond1 "$DESIGN" "$REVIEW"

# Sub-case: design exists, review missing
cat >"$DESIGN" <<'EOF'
# Design
Content.
EOF
assert_fail "precond1: review missing → fail" check_precond1 "$DESIGN" "$REVIEW"

# Sub-case: both exist, review older than design (wrong mtime order)
cat >"$REVIEW" <<'EOF'
# Design Review

**Status:** APPROVED
EOF
# Force design to be newer by touching it
sleep 0.1
touch "$DESIGN"
assert_fail "precond1: design newer than review → fail" check_precond1 "$DESIGN" "$REVIEW"

# Sub-case: both exist, mtime-ordered correctly, status=APPROVED
sleep 0.1
touch "$REVIEW"
assert_pass "precond1: all conditions met, APPROVED → pass" check_precond1 "$DESIGN" "$REVIEW"

# Sub-case: CHANGES REQUESTED in design-review
cat >"$REVIEW" <<'EOF'
# Design Review

**Status:** CHANGES REQUESTED
EOF
sleep 0.1
touch "$REVIEW"
assert_fail "precond1: design-review status=CHANGES REQUESTED → fail" check_precond1 "$DESIGN" "$REVIEW"

# Sub-case: REJECTED in design-review
cat >"$REVIEW" <<'EOF'
# Design Review

**Status:** REJECTED
EOF
sleep 0.1
touch "$REVIEW"
assert_fail "precond1: design-review status=REJECTED → fail" check_precond1 "$DESIGN" "$REVIEW"

# ---------------------------------------------------------------------------
# Section 4: /implement precondition 2
# ---------------------------------------------------------------------------
echo ""
echo "=== 4. /implement precondition 2 (no code-review OR code-review APPROVED) ==="

T="$TMPDIR_ROOT/precond2"
mkdir -p "$T/planning/milestone/reviews"

CODE_REVIEW="$T/planning/milestone/reviews/feature-code-review.md"

# Helper: check precondition 2
check_precond2() {
    local code_review="$1"
    if [ ! -f "$code_review" ]; then
        return 0  # no code-review → first /implement → passes
    fi
    local state
    state=$(head -20 "$code_review" | $GREP -m 1 '^\*\*Status:\*\*' | sed 's/\*\*Status:\*\* //' 2>/dev/null) || return 1
    [ "$state" = "APPROVED" ]
}

# Sub-case: no code-review file → passes (first /implement)
assert_pass "precond2: no code-review file → pass (first /implement)" check_precond2 "$CODE_REVIEW"

# Sub-case: APPROVED code-review → passes
cat >"$CODE_REVIEW" <<'EOF'
# Code Review

**Status:** APPROVED
EOF
assert_pass "precond2: APPROVED code-review → pass" check_precond2 "$CODE_REVIEW"

# Sub-case: CHANGES REQUESTED → fails
cat >"$CODE_REVIEW" <<'EOF'
# Code Review

**Status:** CHANGES REQUESTED
EOF
assert_fail "precond2: CHANGES REQUESTED → fail" check_precond2 "$CODE_REVIEW"

# Sub-case: REJECTED → fails (N3: REJECTED is not APPROVED)
cat >"$CODE_REVIEW" <<'EOF'
# Code Review

**Status:** REJECTED
EOF
assert_fail "precond2: REJECTED → fail (N3)" check_precond2 "$CODE_REVIEW"

# Sub-case: re-/implement after APPROVED code-review (N4: cycle closed, gate passes again)
cat >"$CODE_REVIEW" <<'EOF'
# Code Review

**Status:** APPROVED
EOF
assert_pass "precond2: re-/implement after APPROVED (N4: cycle closed) → pass" check_precond2 "$CODE_REVIEW"

# ---------------------------------------------------------------------------
# Section 5: /complete condition 1 — git clean outside planning/
# ---------------------------------------------------------------------------
echo ""
echo "=== 5. /complete condition 1 (git clean outside planning/) ==="

T="$TMPDIR_ROOT/git_clean"
mkdir -p "$T/planning"

git -C "$T" init -q
git -C "$T" config user.email "test@test.com"
git -C "$T" config user.name "Test"

# Helper: check condition 1
# Returns 0 (pass) if no uncommitted tracked changes outside planning/
check_git_clean() {
    local repo="$1"
    # Get uncommitted changes to tracked files only (exclude untracked lines starting with "??")
    # Filter out lines that refer to planning/ and empty output means clean.
    local changes
    changes=$(git -C "$repo" status --porcelain | $GREP -v '^??' | $GREP -v '^.. planning/' || true)
    [ -z "$changes" ]
}

# Sub-case: clean repo → passes
assert_pass "git_clean: fresh repo with no changes → pass" check_git_clean "$T"

# Sub-case: staged change outside planning/ → fails
echo "content" >"$T/source.go"
git -C "$T" add source.go
assert_fail "git_clean: staged change outside planning/ → fail" check_git_clean "$T"

# Sub-case: only planning/ staged → passes (planning changes in /complete are OK)
git -C "$T" rm --cached source.go >/dev/null 2>&1
rm "$T/source.go"
echo "progress" >"$T/planning/progress.md"
# -f is needed because global gitignore may match planning/* in test environments
git -C "$T" add -f planning/progress.md
assert_pass "git_clean: only planning/ staged → pass" check_git_clean "$T"

# Sub-case: unstaged change outside planning/ → fails
# First commit so HEAD exists, then modify a tracked file
git -C "$T" rm --cached planning/progress.md >/dev/null 2>&1
rm "$T/planning/progress.md"
echo "content" >"$T/source.go"
git -C "$T" add source.go
git -C "$T" commit -q -m "initial"
echo "changed" >>"$T/source.go"
assert_fail "git_clean: unstaged change to tracked file outside planning/ → fail" check_git_clean "$T"

# ---------------------------------------------------------------------------
# Section 6: /complete condition 3 — mocked projctl sync status
# ---------------------------------------------------------------------------
echo ""
echo "=== 6. /complete condition 3 (projctl sync status mocking) ==="

T="$TMPDIR_ROOT/sync_status"
mkdir -p "$T/bin"

# Helper: check condition 3 using a mocked projctl binary
check_sync_status_is_insync() {
    local mock_output="$1"
    # Write a mock projctl that prints the given output and exits 0
    cat >"$T/bin/projctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$mock_output"
exit 0
EOF
    chmod +x "$T/bin/projctl"
    # Run it and check if first line is STATUS: in-sync
    PATH="$T/bin:$PATH" projctl sync status 2>/dev/null | head -1 | $GREP -q '^STATUS: in-sync'
}

assert_pass "sync_status: STATUS: in-sync → pass" check_sync_status_is_insync "STATUS: in-sync"
assert_fail "sync_status: STATUS: remote-ahead → fail" check_sync_status_is_insync "STATUS: remote-ahead"
assert_fail "sync_status: STATUS: local-ahead → fail" check_sync_status_is_insync "STATUS: local-ahead"
assert_fail "sync_status: STATUS: diverged → fail" check_sync_status_is_insync "STATUS: diverged"

# ---------------------------------------------------------------------------
# Section 7: push fragment failure path
# ---------------------------------------------------------------------------
echo ""
echo "=== 7. Push fragment: mock projctl sync push failure → skill succeeds with warning ==="

T="$TMPDIR_ROOT/push_failure"
mkdir -p "$T/bin"

# Mock projctl that fails on sync push
cat >"$T/bin/projctl" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "sync" ] && [ "${2:-}" = "push" ]; then
    echo "Error: Google Drive not mounted" >&2
    exit 1
fi
exit 0
EOF
chmod +x "$T/bin/projctl"

# The fragment logic: run push, capture exit code, surface warning but return 0.
# This simulates what the skill markdown instructs: push failure must not fail the skill.
run_push_fragment() {
    local projctl_bin="$1"
    if "$projctl_bin" sync push 2>/dev/null; then
        return 0
    fi
    # Push failed: surface warning to stderr but return success (skill does not fail)
    echo "⚠️  workflow-safety: planning push failed" >&2
    return 0
}

# Skill must return 0 even when push fails
assert_pass "push_fragment: push failure → skill returns success (0)" run_push_fragment "$T/bin/projctl"

# Warning must contain 'workflow-safety'
WARNING_OUT=$(run_push_fragment "$T/bin/projctl" 2>&1)
echo "$WARNING_OUT" | $GREP -q 'workflow-safety' \
    && pass "push_fragment: warning contains 'workflow-safety'" \
    || fail "push_fragment: warning missing 'workflow-safety'"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
