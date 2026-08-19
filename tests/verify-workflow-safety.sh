#!/usr/bin/env bash
# verify-workflow-safety.sh — gate-primitive regression tests for the workflow-safety milestone.
#
# Exercises the disk-checkable gate conditions defined in design §12.1 without invoking
# Claude Code. Uses a temporary directory for all fixtures; cleans up on exit.
#
# Exit codes: 0 = all tests passed, 1 = one or more tests failed.

# No `-e`. Every sibling suite in this directory runs `set -uo pipefail` for the same reason:
# an assertion here probes for things that are *supposed* to be absent, so a failing grep is
# data, not an error. Under errexit a bare `$(grep ...)` that matches nothing aborts the run
# mid-file — no FAIL line, no summary — which reads as "nothing to report" to a human and to
# an agent scanning output. That happened while this suite was being written.
set -uo pipefail

# Use /usr/bin/grep directly to avoid ugrep alias issues with POSIX character escaping.
GREP=/usr/bin/grep

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Section 0b re-invokes this script against a fixture config. In that mode we run Section 0,
# print the summary, and stop — both to keep the probe cheap and to stop 0b recursing.
SELF_PROBE=0
[ "${1:-}" = "--self-probe" ] && SELF_PROBE=1

# Bump when adding or removing an assertion. Asserted at the end so a section that silently
# skips itself shows up as a count mismatch instead of a green run — the sibling suite added
# the same counter after exactly that defect, and the abort this suite hit is that shape.
EXPECTED_TESTS=63

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

# Two-argument form, matching the three sibling suites: $2 carries the observed-vs-expected
# detail, which for a config-extraction failure is the only thing that names the cause.
# `${2:-}` and the `if`, not `[ -n "$2" ] && echo ...`: assert_pass/assert_fail call this with
# one argument, and the terse form would return 1 there.
fail() {
    echo "  FAIL: $1"
    if [ -n "${2:-}" ]; then
        echo "        $2"
    fi
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

# The four values that define the §4 gate. Section 0 asserts each against the config, so a
# rule change in CLAUDE.md turns this suite red instead of leaving it green against a rule
# that no longer exists. Every gate model in this file is built from them — marker_grep,
# marker_state, check_precond1, check_precond2, and Section 2's fixture arithmetic — so a
# constants update reaches all of them at once.
MARKER_WINDOW=20
MARKER_PATTERN='^\*\*Status:\*\*'
MARKER_STATES='APPROVED|CHANGES REQUESTED|REJECTED'
# Anchored, matching the enforcement site: commands/implement.md strips with
# `sed 's/^\*\*Status:\*\* //'`. An unanchored copy would also strip a mid-line occurrence.
MARKER_STRIP='s/^\*\*Status:\*\* //'

# The grep pattern the gates use, applied to a file: finds the status line.
marker_grep() {
    local file="$1"
    head -"$MARKER_WINDOW" "$file" | $GREP -m 1 "$MARKER_PATTERN"
}

# Extract just the state value after "**Status:** "
marker_state() {
    local file="$1"
    marker_grep "$file" | sed "$MARKER_STRIP"
}

# Check if a marker state is canonical (one of the states the config allows).
# The `-n` test is load-bearing: a malformed MARKER_STATES — empty, or with a leading or
# trailing `|` — makes tr emit an empty token, and without it an empty state would match
# and read as canonical. That is the one direction this gate must never fail.
is_canonical_state() {
    local state="$1" allowed
    while IFS= read -r allowed; do
        [ -n "$allowed" ] && [ "$state" = "$allowed" ] && return 0
    done < <(printf '%s\n' "$MARKER_STATES" | tr '|' '\n')
    return 1
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
# Section 0: the constants above must be the ones the config actually mandates
# ---------------------------------------------------------------------------
# Every other section here runs on synthetic fixtures and reads no config file, so before
# this section the suite validated the test author's memory of the gate rather than the
# gate itself. If CLAUDE.md changed its window, its grep pattern, or its allowed-state
# list, the suite stayed green while `/implement` and `/complete` enforced something else.
echo ""
echo "=== 0. Gate constants match the config that mandates them ==="

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$REPO_ROOT/platforms/claude"
# Overridable so the extraction can be driven against a fixture config — Section 0b needs a
# document whose anchor is missing, and pointing at the real tree cannot produce one.
CLAUDE_MD="${CLAUDE_MD_OVERRIDE:-$CLAUDE_DIR/CLAUDE.md}"
MARKER_SKILL="$CLAUDE_DIR/skills/workflows/status-marker-verify/SKILL.md"

# Extract §4's values from the named section only. Whole-file greps were wrong twice over:
# an unrelated `Allowed states:` sentence elsewhere in the file produced a second match, and
# a stale duplicate of the command could satisfy the cross-check while the live statement
# disagreed. sed range from the §4 heading to the next `###` bounds it.
section_of() {   # section_of <file> <heading-regex>
    sed -n "/^#\{1,4\} $2/,/^#\{1,3\} /p" "$1" 2>/dev/null
}

# All three extractions pull the backtick-quoted tokens rather than a punctuation-delimited
# run. The earlier form terminated `cfg_states` on a period and the skill's on an em dash —
# an asymmetry that existed only because each document happens to punctuate that sentence
# differently, and that turned red on any benign reword.
states_of() {    # states_of <section-text> -> APPROVED|CHANGES REQUESTED|REJECTED
    printf '%s\n' "$1" | $GREP -o 'Allowed states:[^.]*' | head -1 \
        | $GREP -o '`[A-Z][A-Z ]*`' | tr -d '`' | paste -sd '|' -
}

cfg_section=$(section_of "$CLAUDE_MD" 'Review File Status-Marker Convention')
cfg_cmd=$(printf '%s\n' "$cfg_section" | $GREP -o 'Machine-readable via `[^`]*`' \
          | sed 's/^Machine-readable via `//; s/`$//')
cfg_cmd_n=$(printf '%s\n' "$cfg_section" | $GREP -c 'Machine-readable via `')
cfg_window=$(printf '%s' "$cfg_cmd" | sed -n "s/^head -\([0-9]\{1,\}\) .*/\1/p")
cfg_pattern=$(printf '%s' "$cfg_cmd" | sed -n "s/.*grep -m 1 '\(.*\)'\$/\1/p")
cfg_states=$(states_of "$cfg_section")
cfg_prose_window=$(printf '%s\n' "$cfg_section" \
                   | sed -n 's/.*within the first \([0-9]\{1,\}\) lines.*/\1/p' | head -1)

# The guard earns its place by checking the values PARSE, not merely that they are non-empty:
# every comparison below is against a non-empty literal, so an empty extraction already
# reddens its own assertion. What nothing else covers is a window that is not a number or a
# state list that is not three fields — an extraction that succeeded on the wrong text.
state_count=$(printf '%s\n' "$cfg_states" | tr '|' '\n' | $GREP -c .)
if [ "$cfg_cmd_n" = "1" ] && printf '%s' "$cfg_window" | $GREP -qx '[0-9]\{1,\}' \
   && [ -n "$cfg_pattern" ] && [ "$state_count" = "3" ]; then
    pass "§4 parses: exactly one command, a numeric window, a pattern, three states"
else
    fail "§4 parses: exactly one command, a numeric window, a pattern, three states" \
         "matches=$cfg_cmd_n window='$cfg_window' pattern='$cfg_pattern' states='$cfg_states' ($state_count fields)"
fi

if [ "$cfg_window" = "$MARKER_WINDOW" ]; then
    pass "gate window matches CLAUDE.md §4 (head -$MARKER_WINDOW)"
else
    fail "gate window matches CLAUDE.md §4" "config says '$cfg_window', suite uses '$MARKER_WINDOW'"
fi

# §4 states the window twice — in the runnable command and in prose. They can drift apart.
if [ "$cfg_prose_window" = "$cfg_window" ]; then
    pass "§4's prose window agrees with its own runnable command"
else
    fail "§4's prose window agrees with its own runnable command" \
         "prose says '$cfg_prose_window', command says '$cfg_window'"
fi

if [ "$cfg_pattern" = "$MARKER_PATTERN" ]; then
    pass "gate grep pattern matches CLAUDE.md §4"
else
    fail "gate grep pattern matches CLAUDE.md §4" \
         "config says '$cfg_pattern', suite uses '$MARKER_PATTERN'"
fi

if [ "$cfg_states" = "$MARKER_STATES" ]; then
    pass "allowed states match CLAUDE.md §4 ($MARKER_STATES)"
else
    fail "allowed states match CLAUDE.md §4" "config says '$cfg_states', suite uses '$MARKER_STATES'"
fi

# The convention is restated in the fragment the review commands invoke. A disagreement means
# a review file can satisfy the command that wrote it and fail the gate that reads it.
skill_states=$(states_of "$(section_of "$MARKER_SKILL" 'Convention')")
if [ -n "$skill_states" ] && [ "$skill_states" = "$cfg_states" ]; then
    pass "status-marker-verify agrees with CLAUDE.md §4 on the allowed states"
else
    fail "status-marker-verify agrees with CLAUDE.md §4 on the allowed states" \
         "skill='$skill_states' claude='$cfg_states'"
fi

# Every site that restates the runnable gate command must agree with §4. The needle is built
# from the EXTRACTED §4 values, not from this suite's constants — building it from the
# constants made the assertion green on the very divergence it names, since it then compared
# the site against the suite rather than against §4.
#
# commands/implement.md is the reason this list is not just the skill: those two sites are
# the gate `/implement` actually runs. §4 is documentation; that file is enforcement.
gate_sites="commands/implement.md
skills/workflows/status-marker-verify/SKILL.md
agents/reviewer.md
commands/review-code-fix-loop.md
commands/review-design-fix-loop.md
commands/review-article-fix-loop.md"

# Placeholders differ per site (<file>, <review_file>, "$REVIEW", a literal path), so compare
# the invariant part: the window and the pattern in one head|grep pipeline.
needle_head="head -$cfg_window"
needle_grep="grep -m 1 '$cfg_pattern'"
mismatched=""
site_count=0
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    f="$CLAUDE_DIR/$rel"
    if [ ! -f "$f" ]; then mismatched="$mismatched  $rel (file absent)\n"; continue; fi
    site_count=$((site_count + 1))
    # Every line holding the gate pipeline must carry §4's window and §4's pattern.
    while IFS= read -r line; do
        case "$line" in
            *"$needle_head"*"$needle_grep"*) ;;
            *) mismatched="$mismatched  $rel: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-90)\n" ;;
        esac
    done < <($GREP -h "grep -m 1 '" "$f")
done <<EOF
$gate_sites
EOF

if [ "$site_count" -lt 6 ]; then
    fail "all 6 gate restatement sites were found and read" "read only $site_count"
elif [ -z "$mismatched" ]; then
    pass "all $site_count sites restating the gate command agree with §4 (head -$cfg_window)"
else
    fail "all $site_count sites restating the gate command agree with §4 (head -$cfg_window)" \
         "$(printf "%b" "$mismatched")"
fi

# The strip expression is the fourth gate fragment and the only one §4 does not publish, so
# it is pinned against the enforcement site directly. It is also the one that already
# diverged: this suite stripped unanchored while implement.md anchors.
impl_strip=$($GREP -o "sed 's/[^']*Status:[^']*'" "$CLAUDE_DIR/commands/implement.md" \
             | sed "s/^sed '//; s/'$//" | sort -u)
impl_strip_n=$(printf '%s\n' "$impl_strip" | $GREP -c .)
if [ "$impl_strip_n" = "1" ] && [ "$impl_strip" = "$MARKER_STRIP" ]; then
    pass "state-strip expression matches commands/implement.md"
else
    fail "state-strip expression matches commands/implement.md" \
         "implement.md has $impl_strip_n distinct form(s): '$impl_strip'; suite uses '$MARKER_STRIP'"
fi

if [ "$SELF_PROBE" -eq 1 ]; then
    echo ""
    echo "========================================"
    echo "Results: $PASS passed, $FAIL failed"
    echo "========================================"
    exit 0
fi

# ---------------------------------------------------------------------------
# Section 0b: Section 0 must report, not abort, when extraction finds nothing
# ---------------------------------------------------------------------------
# Regression test. An earlier form of Section 0 used bare `$(grep ...)` under `set -e`: with
# the §4 anchor absent the run died mid-file — zero FAIL lines, no summary, exit 1 — and the
# guard meant to catch exactly that never executed. Silence read as success. This drives the
# real suite against a config whose anchor is gone and asserts the run still *reports*.
echo ""
echo "=== 0b. Extraction failure is reported, not fatal ==="

T="$TMPDIR_ROOT/extraction"
mkdir -p "$T"
sed 's/Machine-readable via /Checked via /' "$CLAUDE_DIR/CLAUDE.md" >"$T/no-anchor.md"

if $GREP -q 'Machine-readable via ' "$T/no-anchor.md"; then
    fail "fixture actually removes the extraction anchor" "the sed did not match — fixture is not exercising the case"
else
    pass "fixture actually removes the extraction anchor"
fi

# Run this same script with the fixture substituted in. CLAUDE_MD_OVERRIDE is the only reason
# CLAUDE_MD is indirect; without it the case cannot be reached from a test at all.
# `|| true` is load-bearing even though this suite has no `-e` today: the probe exits non-zero
# by design, so if errexit is ever restored this assignment would abort the outer run at the
# very line meant to detect that — the guard would take the whole suite down with it.
probe=$(CLAUDE_MD_OVERRIDE="$T/no-anchor.md" bash "$0" --self-probe 2>&1) || true

if printf '%s\n' "$probe" | $GREP -q '^  FAIL: §4 parses'; then
    pass "missing anchor produces a named FAIL line"
else
    fail "missing anchor produces a named FAIL line" \
         "no '§4 parses' FAIL in output; first lines: $(printf '%s\n' "$probe" | head -3 | tr '\n' '/')"
fi

# The summary line is the assertion that matters: it is what proves the run reached the end
# rather than dying at the extraction.
if printf '%s\n' "$probe" | $GREP -q '^Results: [0-9]\{1,\} passed, [0-9]\{1,\} failed$'; then
    pass "missing anchor still reaches the Results summary"
else
    fail "missing anchor still reaches the Results summary" \
         "no Results line — the run aborted mid-file, which is the defect this guards"
fi

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

# One reject fixture per distinct rejection mode. The pre-convention fixture above differs
# from canonical in three ways at once (emoji, case, trailing words), so it cannot show which
# rule does the rejecting. These isolate one deviation each — is_canonical_state is the only
# definition of "canonical" in this file, and it was rewritten from a `case` statement.
reject_fixture() {   # reject_fixture <name> <marker-line>
    printf '# Review Summary\n\n%s\n\nBody.\n' "$2" >"$T/$1.md"
}
reject_fixture case_variant   '**Status:** Approved'
reject_fixture trailing_ws    '**Status:** APPROVED '
reject_fixture empty_value    '**Status:**'
printf '# Review Summary\r\n\r\n**Status:** APPROVED\r\n' >"$T/crlf.md"

# The realistic near-miss: the convention exists because agents write mixed case.
assert_fail "Case variant 'Approved' is not canonical"      marker_gate_pass "$T/case_variant.md"
assert_fail "Trailing whitespace is not canonical"          marker_gate_pass "$T/trailing_ws.md"
assert_fail "Bare '**Status:**' with no value is not canonical" marker_gate_pass "$T/empty_value.md"
assert_fail "CRLF line ending is not canonical"             marker_gate_pass "$T/crlf.md"

# The empty-token fail-open guard in is_canonical_state, exercised directly: a malformed
# constant must not make an empty state read as canonical.
(
    MARKER_STATES='APPROVED|REJECTED|'
    is_canonical_state ""
) && fail "empty state rejected when MARKER_STATES has a trailing separator" \
          "is_canonical_state '' returned 0 — the fail-open guard is gone" \
  || pass "empty state rejected when MARKER_STATES has a trailing separator"

# ---------------------------------------------------------------------------
# Section 2: Marker location — within the window MARKER_WINDOW names
# ---------------------------------------------------------------------------
echo ""
echo "=== 2. Marker location: within first $MARKER_WINDOW lines ==="

T="$TMPDIR_ROOT/marker_location"
mkdir -p "$T"

# Marker on line 2 (immediately after H1, no blank line)
{
    printf "# Review Summary\n"
    printf "**Status:** APPROVED\n"
} >"$T/line2.md"
assert_pass "Marker on line 2 found" marker_grep "$T/line2.md"

# Marker on the last line inside the window
{
    printf "# Review Summary\n"
    for i in $(seq 1 $((MARKER_WINDOW - 2))); do printf "line %d\n" "$i"; done
    printf "**Status:** APPROVED\n"
} >"$T/line20.md"
LINE_COUNT=$(wc -l <"$T/line20.md")
[ "$LINE_COUNT" -eq "$MARKER_WINDOW" ] && pass "line20.md has exactly $MARKER_WINDOW lines" || fail "line20.md has $LINE_COUNT lines" "expected $MARKER_WINDOW"
assert_pass "Marker on line $MARKER_WINDOW found" marker_grep "$T/line20.md"

# Marker one line past the window — must NOT be found
{
    printf "# Review Summary\n"
    for i in $(seq 1 $((MARKER_WINDOW - 1))); do printf "line %d\n" "$i"; done
    printf "**Status:** APPROVED\n"
} >"$T/line21.md"
assert_fail "Marker on line $((MARKER_WINDOW + 1)) not found (beyond head -$MARKER_WINDOW)" marker_grep "$T/line21.md"

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
    state=$(marker_state "$review" 2>/dev/null) || return 1
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
    state=$(marker_state "$code_review" 2>/dev/null) || return 1
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
# Section 8: fix-loop cap mechanism — the shared fragment plus the three fix loops
# ---------------------------------------------------------------------------
# Every assertion here is static document agreement: nothing executes a command file, so
# what can be checked is that the fragment and the three loops that read it still say what
# they must for the cap to fire once, at the right count, and hand off to the right block.
echo ""
echo "=== 8. Fix-loop cap mechanism (fragment + three fix loops) ==="

FRAGMENT="$CLAUDE_DIR/skills/workflows/fix-loop-round/SKILL.md"
LOOP_CODE="$CLAUDE_DIR/commands/review-code-fix-loop.md"
LOOP_DESIGN="$CLAUDE_DIR/commands/review-design-fix-loop.md"
LOOP_ARTICLE="$CLAUDE_DIR/commands/review-article-fix-loop.md"
ITERATE_CMD="$CLAUDE_DIR/commands/review-iterate.md"
FIXLOOPS="$LOOP_CODE $LOOP_DESIGN $LOOP_ARTICLE"

# Text between a heading line matching $2 and the next heading matching $3, both exclusive.
# Scoping to one block is what makes a mutation elsewhere in the file invisible to the wrong
# assertion — a stray "Step 4" in some other step must not trip a check that is about Step 3.
section_between() {
    awk -v start="$2" -v stop="$3" '
        $0 ~ start { f=1; next }
        f && $0 ~ stop { exit }
        f { print }
    ' "$1"
}

# Each fix loop's Step 3 must read the fragment BEFORE launching its own review pass — a
# fragment read after the launch sentence runs the review pass once as that sentence's own
# instruction and a second time as the fragment's position 2, which is the doubled pass this
# mechanism exists to remove. Step 3 must also name no destination of its own for a verdict
# and increment nothing itself — the fragment's position 1 is the only increment site, and a
# loop that keeps its own increment fires the cap after two cycles, not three. Each loop's
# preamble must still initialise `iteration` on its own line, since it is now the only thing
# the cap is decided from. The fragment's own position 1 is checked too, not just what the
# loops do or do not repeat from it — a table row that stops naming the increment leaves
# `iteration` at 0 forever, and every non-APPROVED verdict then matches "below the cap" with
# every other assertion here green, which is ledger entry 1's observed symptom restored by a
# one-cell edit.
#
# Design §5.3 states what Step 3 is left holding: its launch sentence, its prior-review
# pass-through, the fragment `Read` pointer, and nothing that routes on a verdict or touches
# `iteration`. A grep for one destination phrase ('return to Step 2') or one increment phrase
# only proves those exact words are absent — a synonym ('restart the fix at Step 2', 'Bump
# `iteration` by one', 'Advance the round counter by one') passes the same broken loop through
# untouched. Asserting the shape instead — strip the `Read` pointer line and the disclosure
# sentence, anchored on both its own start and its own end so text appended to that same
# unwrapped line survives the strip instead of leaving with it — and require the remainder
# name no `Step [0-9]`, no `iteration`, and no `counter` — catches every phrasing this repo
# has actually produced, not a closed set of every possible paraphrase.
# H2's guard: everywhere outside Step 3, the ONLY lines that may name iteration/counter are a
# fixed set verified against each file — the frontmatter description, the H1 summary, the
# Preamble, and the cap/summary message templates. A verb-list blacklist (reset|increment|
# bump|advance ...) is a closed set ordinary English slips past — "Set `iteration` to 0" or
# "Zero the round counter" name neither verb. Whitelisting by full exact line text closes that:
# any line outside Step 3 naming iteration/counter that is not one of the verified lines fails,
# whatever verb — or none — it uses. Matching by exact text rather than substring is also what
# catches a reworded Preamble: rewording it to bury a reset ("...and is reset to 0 at the start
# of each fix pass") no longer equals the whitelisted line, so it is no longer exempted by
# virtue of merely being "the Preamble line".
allowed_counter_lines() {   # allowed_counter_lines <file> -> that file's whitelisted lines naming iteration/counter, one per line
    case "$1" in
        "$LOOP_CODE") cat <<'EOF'
description: Run initial code review, fix all findings, re-review until APPROVED or the iteration cap, then print the report
Run the full code review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED or the iteration cap → report.
**Preamble:** Initialize `iteration = 0` before Step 0. This counter is set exactly once at command start and is never reset mid-run.
Code review loop paused — iteration cap reached
Iterations completed: [iteration]
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
EOF
            ;;
        "$LOOP_DESIGN") cat <<'EOF'
description: Run initial design review, fix all findings, re-review until APPROVED or the iteration cap, then print the report
Run the full design review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED or the iteration cap → report.
**Preamble:** Initialize `iteration = 0` and `design_modified = false` before Step 1. These are set exactly once at command start and never reset mid-run. Invariant: `**Revision:**` in `design.md` is incremented at most once per invocation — in Step 5 (or any earlier terminal stop path) — contingent on `design_modified = true`.
Iterations completed: [iteration]
Design review loop paused — iteration cap reached
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
EOF
            ;;
        "$LOOP_ARTICLE") cat <<'EOF'
description: Run initial article review, fix all High and Medium findings, re-review until APPROVED or the iteration cap, then print the report
Run the full article review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED or the iteration cap → report.
**Preamble:** Initialize `iteration = 0` before Step 1. Set exactly once at command start; never reset mid-run.
Iterations completed: [iteration]
Article review loop paused — iteration cap reached
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
EOF
            ;;
    esac
}

# The one whitelisted line that also has to positively exist — the others are permitted, but
# this one is required, since a caller could delete its Preamble line entirely and this file's
# candidate-line scan would then have nothing left to flag as unrecognised.
preamble_whitelist_line() {   # preamble_whitelist_line <file> -> that file's expected Preamble line
    allowed_counter_lines "$1" | $GREP -F '**Preamble:**'
}

counter_mutation_lines() {   # counter_mutation_lines <file> -> lines outside Step 3 naming iteration/counter that are not on the file's whitelist
    local allowed
    allowed=$(allowed_counter_lines "$1")
    awk '
        /^### Step 3:/ { skip=1; next }
        skip && /^### / { skip=0 }
        !skip { print }
    ' "$1" | $GREP -iE '\b(iteration|counter)\b' | while IFS= read -r line; do
        printf '%s\n' "$allowed" | $GREP -qxF "$line" || printf '%s\n' "$line"
    done
}
bad=""
for f in $FIXLOOPS; do
    step3=$(section_between "$f" '^### Step 3:' '^### ')
    printf '%s' "$step3" | $GREP -qF 'Read ~/.claude/skills/workflows/fix-loop-round/SKILL.md' \
        || bad="$bad${f#"$CLAUDE_DIR"/}: Step 3 missing the fragment Read pointer; "
    read_line=$(printf '%s\n' "$step3" | $GREP -n 'Read ~/.claude/skills/workflows/fix-loop-round/SKILL.md' | head -1 | cut -d: -f1)
    follow_line=$(printf '%s\n' "$step3" | $GREP -n '^Follow `/review-' | head -1 | cut -d: -f1)
    if [ -z "$read_line" ] || [ -z "$follow_line" ] || [ "$read_line" -ge "$follow_line" ]; then
        bad="$bad${f#"$CLAUDE_DIR"/}: Step 3's fragment Read does not precede the review-pass launch sentence; "
    fi
    # Anchored on both ends, matching the disclosure strip beside it: a `grep -vF` substring
    # strip deletes the WHOLE line it matches, so text appended onto the same unwrapped Read
    # line — an increment or a destination clause riding along with it — left with the line
    # it hid inside, unseen by the shape check below.
    step3_shape=$(printf '%s\n' "$step3" \
        | $GREP -vE '^Read ~/\.claude/skills/workflows/fix-loop-round/SKILL\.md$' \
        | $GREP -vE '^\*\*This file is parsed by two tests\.\*\*.*without re-running both is how this drifts silently\.$')
    printf '%s' "$step3_shape" | $GREP -qE 'Step [0-9]|iteration|counter' \
        && bad="$bad${f#"$CLAUDE_DIR"/}: Step 3 names a destination step, touches iteration, or touches a counter outside the fragment; "
    mut=$(counter_mutation_lines "$f")
    n_mut=$(printf '%s\n' "$mut" | $GREP -c . || true)
    if [ "$n_mut" -ne 0 ]; then
        bad="$bad${f#"$CLAUDE_DIR"/}: iteration/counter named outside Step 3 by $n_mut line(s) not on the whitelist: $(printf '%s' "$mut" | tr '\n' '|'); "
    fi
    if ! $GREP -qxF "$(preamble_whitelist_line "$f")" "$f"; then
        bad="$bad${f#"$CLAUDE_DIR"/}: Preamble no longer carries the whitelisted \`iteration = 0\` initialisation line; "
    fi
done
# The fragment's `## The Round` position table is one copy read by every loop (§5.1) — its
# row 1 is the counter's only increment site. Scanning the whole fragment for the first
# `^| 1 |` line, rather than this table specifically, lets a decoy row placed earlier in the
# fragment win first-match and stand in for the real one; scoping to the section and requiring
# exactly the three rows in order closes that.
round_section=$(section_between "$FRAGMENT" '^## The Round' '^## ')
pos_rows=$(printf '%s\n' "$round_section" | $GREP -E '^\| [0-9]+ \|')
n_pos_rows=$(printf '%s\n' "$pos_rows" | $GREP -c . || true)
pos1=$(printf '%s\n' "$pos_rows" | sed -n '1p')
pos2=$(printf '%s\n' "$pos_rows" | sed -n '2p')
pos3=$(printf '%s\n' "$pos_rows" | sed -n '3p')
if [ "$n_pos_rows" -ne 3 ] || [ "$pos1" != '| 1 | increment `iteration` |' ] \
   || [ "$pos2" != '| 2 | run the review pass |' ] || [ "$pos3" != '| 3 | branch on the result |' ]; then
    bad="${bad}fragment's \`## The Round\` position table is not exactly rows 1-3 in order (increment iteration, run the review pass, branch on the result) — found $n_pos_rows row(s): 1='$pos1' 2='$pos2' 3='$pos3'; "
fi
if [ -z "$bad" ]; then
    pass "each fix loop's Step 3 reads the fragment before launching its review pass, names no destination, increments nothing, each preamble initialises iteration, and the fragment's own position 1 is the sole increment site"
else
    fail "each fix loop's Step 3 reads the fragment before launching its review pass, names no destination, increments nothing, each preamble initialises iteration, and the fragment's own position 1 is the sole increment site" "$bad"
fi

# The fragment's three not-APPROVED rows must stay in stall, below-cap, at-or-above-cap
# order — a stall row moved below either cap row is unreachable while the loop still has
# cycles left, losing the unresolved-area name that is the whole content of the stall
# message. Each row's Condition and Next cells are extracted as their own columns and
# compared by exact value, not searched for anywhere in the row — a whole-row substring
# search is satisfied by a Condition cell that has been widened to swallow every iteration
# count while still containing the search term, or by a Next cell that keeps a heading's name
# as trailing prose while actually routing elsewhere ("Step 2, not the calling loop's
# `### Cap-pause`"). There must also be exactly one APPROVED row and exactly four rows in the
# table overall: the two verdict-token greps below only see rows whose Verdict cell already
# reads `APPROVED` or `not APPROVED`, so a decoy row under a third token (`REJECTED`,
# `CHANGES REQUESTED`) is invisible to both counts and grows the table underneath them; the
# structural row count catches it regardless of what token the decoy carries.
# Positional from the start ($4), mirroring middle_cell's $3 below — NOT from the end
# ($(NF-1)). A row with any cell count other than exactly 3 body cells agrees with a
# start-anchored and an end-anchored read only by accident; the NF==5 gate the branch-table
# assertion applies to every counted row (below) is what catches a wrong cell count, so this
# function can stay positional instead of guessing from the end where "last" might land on
# whatever cell a malformed row happens to have there.
last_cell() {   # last_cell <table-row> -> the row's Next cell, trimmed
    printf '%s' "$1" | awk -F'|' '{c=$4; gsub(/^[ \t]+|[ \t]+$/, "", c); print c}'
}
# Mirrors last_cell but reads the Condition column — always field 3 in this table's fixed
# Verdict | Condition | Next shape.
middle_cell() {   # middle_cell <table-row> -> the row's Condition cell, trimmed
    printf '%s' "$1" | awk -F'|' '{c=$3; gsub(/^[ \t]+|[ \t]+$/, "", c); print c}'
}
# Everything between the table's header and the first line that is not itself a table row —
# independent of what any row's Verdict cell says, so an inserted row is counted even when its
# Verdict token matches neither of the greps below.
branch_table_rows() {
    awk '
        /^\| Verdict \| Condition \| Next \|$/ { f=1; next }
        f && /^\|/ { print; next }
        f { exit }
    ' "$FRAGMENT" | $GREP -v '^|---'
}
n_table_rows=$(branch_table_rows | $GREP -c . || true)
# Every counted row must be exactly 3 body cells — 5 fields under -F'|' (leading empty,
# Verdict, Condition, Next, trailing empty). A row with a different cell count is what let
# last_cell's old end-anchored $(NF-1) read the wrong column and still agree with the
# expected value by accident; failing the count here means a malformed row is caught on the
# count, before last_cell or middle_cell ever reads it at all.
bad_field_count=""
while IFS= read -r row; do
    [ -n "$row" ] || continue
    nf=$(printf '%s' "$row" | awk -F'|' '{print NF}')
    [ "$nf" -eq 5 ] || bad_field_count="$bad_field_count(nf=$nf: '$row') "
done <<EOF
$(branch_table_rows)
EOF
approved_rows=$($GREP -n '^| APPROVED |' "$FRAGMENT" | sed -E 's/^[0-9]+://')
n_approved=$(printf '%s\n' "$approved_rows" | $GREP -c . || true)
approved_row=$(printf '%s\n' "$approved_rows" | sed -n '1p')
rows=$($GREP -n '^| not APPROVED |' "$FRAGMENT" | sed -E 's/^[0-9]+://')
n_rows=$(printf '%s\n' "$rows" | $GREP -c . || true)
stall_row=$(printf '%s\n' "$rows" | sed -n '1p')
below_row=$(printf '%s\n' "$rows" | sed -n '2p')
cap_row=$(printf '%s\n' "$rows" | sed -n '3p')
if [ "$n_table_rows" -eq 4 ] && [ -z "$bad_field_count" ] && [ "$n_rows" -eq 3 ] && [ "$n_approved" -eq 1 ] \
   && [ "$(middle_cell "$stall_row")" = 'stall condition met' ] \
   && [ "$(last_cell "$stall_row")" = "the calling loop's \`### Stall stop\`" ] \
   && [ "$(middle_cell "$below_row")" = '`iteration` below the cap' ] \
   && [ "$(last_cell "$below_row")" = 'Step 2' ] \
   && [ "$(middle_cell "$cap_row")" = '`iteration` at or above the cap' ] \
   && [ "$(last_cell "$cap_row")" = "the calling loop's \`### Cap-pause\`" ] \
   && [ "$(last_cell "$approved_row")" = 'Step 5' ]; then
    pass "fragment's branch table has exactly 4 rows — 1 APPROVED and 3 not-APPROVED in order stall, below cap, at-or-above cap — each row exactly 3 body cells, each Condition and Next cell matched by exact value, not substring"
else
    fail "fragment's branch table has exactly 4 rows — 1 APPROVED and 3 not-APPROVED in order stall, below cap, at-or-above cap — each row exactly 3 body cells, each Condition and Next cell matched by exact value, not substring" \
         "n_table_rows=$n_table_rows bad_field_count='$bad_field_count' n_rows=$n_rows n_approved=$n_approved approved='$approved_row' stall='$stall_row' below='$below_row' cap='$cap_row'"
fi

# The cap row itself must read "at or above the cap" — equality would let an overshooting
# counter run one round past the pause. Whitespace-tolerant: an exact literal-string match
# reports the wrong cause (a stray extra space) as if the wording itself had regressed.
if printf '%s' "$cap_row" | $GREP -qE 'not APPROVED[[:space:]]*\|[[:space:]]*`iteration`[[:space:]]*at or above the cap'; then
    pass "fragment's cap row reads 'at or above the cap', not 'equal to'"
else
    fail "fragment's cap row reads 'at or above the cap', not 'equal to'" \
         "cap row: '$cap_row'"
fi

# "final clean review" must be gone from all three loops, including frontmatter — a
# surviving mention in the description is a promise the body no longer keeps.
hits=""
for f in $FIXLOOPS; do
    $GREP -qi 'final clean review' "$f" && hits="$hits${f#"$CLAUDE_DIR"/} "
done
if [ -z "$hits" ]; then
    pass "'final clean review' (case-insensitive) is absent from all three fix loops, including frontmatter"
else
    fail "'final clean review' (case-insensitive) is absent from all three fix loops, including frontmatter" \
         "found in: $hits"
fi

# Every Step <N> / Steps <N> and <M> reference inside a fix loop, other than one qualified
# by another command's name ("Step 7 in `/review-code`"), must resolve to a "### Step <N>"
# heading in that same file. Every step number the fragment itself names (its Next column
# routes to Step 5 and Step 2) must resolve in each of the three loops that read it. A
# partial deletion leaves a dangling reference; a fragment routing a verdict to a step no
# loop has is the same failure from the other side.
# Recognises Step <N>, Steps <N> and/or <M>, the comma list Steps <N>, <M>, <K>, and the
# en/em-dash or hyphen range Steps <N>-<M> — the forms design.md §5.4 names. A qualified
# reference ("Step 0 of `/review-design`") has only its qualified span erased, not its whole
# line: dropping the whole line used to blank any co-located local reference on the same
# unwrapped paragraph, which is what let a reworded local Step number pass unseen.
extract_step_nums() {   # extract_step_nums <file> -> one referenced step number per line
    sed -E 's/Steps? [0-9]+(, ?[0-9]+| and [0-9]+| or [0-9]+|[–—-][0-9]+)* (in|of) `\/[^`]*`//g' "$1" \
        | $GREP -oE 'Steps? [0-9]+(, ?[0-9]+| and [0-9]+| or [0-9]+|[–—-][0-9]+)*' \
        | while IFS= read -r ref; do
            if printf '%s' "$ref" | $GREP -qE '[–—-]'; then
                # Range form: expand N-M inclusive rather than keeping only the two endpoints.
                lo=$(printf '%s' "$ref" | $GREP -oE '[0-9]+' | head -1)
                hi=$(printf '%s' "$ref" | $GREP -oE '[0-9]+' | tail -1)
                seq "$lo" "$hi"
            else
                printf '%s' "$ref" | $GREP -oE '[0-9]+'
            fi
        done | sort -u
}
existing_step_headings() {   # existing_step_headings <file> -> one heading's step number per line
    $GREP -oE '^### Step [0-9]+' "$1" | $GREP -oE '[0-9]+' | sort -u
}
bad=""
for f in $FIXLOOPS; do
    refs=$(extract_step_nums "$f")
    headings=$(existing_step_headings "$f")
    unresolved=$(comm -23 <(printf '%s\n' "$refs") <(printf '%s\n' "$headings") 2>/dev/null | $GREP -v '^$' || true)
    [ -n "$unresolved" ] && bad="$bad${f#"$CLAUDE_DIR"/}: references Step(s) $(printf '%s' "$unresolved" | tr '\n' ',')  with no matching heading; "
done
frag_refs=$(extract_step_nums "$FRAGMENT")
for f in $FIXLOOPS; do
    headings=$(existing_step_headings "$f")
    missing=$(comm -23 <(printf '%s\n' "$frag_refs") <(printf '%s\n' "$headings") 2>/dev/null | $GREP -v '^$' || true)
    [ -n "$missing" ] && bad="$bad${f#"$CLAUDE_DIR"/}: fragment names Step(s) $(printf '%s' "$missing" | tr '\n' ',') this loop has no heading for; "
done
if [ -z "$bad" ]; then
    pass "every Step <N> reference in the fix loops resolves to a heading, and every step the fragment names resolves in all three loops"
else
    fail "every Step <N> reference in the fix loops resolves to a heading, and every step the fragment names resolves in all three loops" "$bad"
fi

# Each loop must hold "### Cap-pause" and "### Stall stop" under the exact names the
# fragment's branch table routes to, and each loop's Cap-pause must run its own cleanup and
# revision steps before review-planning-update, giving review-planning-update all five
# parameters (issue_folder included) — the shape the fragment fixes once and no loop restates.
bad=""
$GREP -qF '`### Cap-pause`' "$FRAGMENT" || bad="${bad}fragment does not route to \`### Cap-pause\` by name; "
$GREP -qF '`### Stall stop`' "$FRAGMENT" || bad="${bad}fragment does not route to \`### Stall stop\` by name; "
for f in $FIXLOOPS; do
    $GREP -qE '^### Cap-pause' "$f" || bad="$bad${f#"$CLAUDE_DIR"/}: no ### Cap-pause heading; "
    $GREP -qE '^### Stall stop' "$f" || bad="$bad${f#"$CLAUDE_DIR"/}: no ### Stall stop heading; "
done

# The fragment's §5.2 obligation is "all five parameters" — issue_folder, approved_phase,
# review_label, approved_next, escalation — not issue_folder alone. Each is written as
# `name = value` at the call site, so a bare name-prefix match finds every one regardless of
# its per-loop value.
rpu_params_missing() {   # rpu_params_missing <cap-block-text> -> missing param names, space-separated
    local block="$1" missing="" p
    for p in issue_folder approved_phase review_label approved_next escalation; do
        printf '%s' "$block" | $GREP -qF "$p = " || missing="$missing$p "
    done
    printf '%s' "$missing"
}

cap_code=$(section_between "$LOOP_CODE" '^### Cap-pause' '^### ')
printf '%s' "$cap_code" | $GREP -qF 'review-planning-update/SKILL.md' \
    || bad="${bad}review-code-fix-loop.md Cap-pause: does not run review-planning-update; "
missing=$(rpu_params_missing "$cap_code")
[ -n "$missing" ] && bad="${bad}review-code-fix-loop.md Cap-pause: review-planning-update missing parameter(s): $missing; "
printf '%s' "$cap_code" | $GREP -qF 'design-revision-bump' \
    && bad="${bad}review-code-fix-loop.md Cap-pause: runs design-revision-bump, which this loop does not own; "

cap_design=$(section_between "$LOOP_DESIGN" '^### Cap-pause' '^### ')
bump_line=$(printf '%s\n' "$cap_design" | $GREP -n 'design-revision-bump' | head -1 | cut -d: -f1)
rpu_line=$(printf '%s\n' "$cap_design" | $GREP -n 'review-planning-update/SKILL.md' | head -1 | cut -d: -f1)
if [ -z "$bump_line" ] || [ -z "$rpu_line" ] || [ "$bump_line" -ge "$rpu_line" ]; then
    bad="${bad}review-design-fix-loop.md Cap-pause: design-revision-bump does not run before review-planning-update; "
fi
missing=$(rpu_params_missing "$cap_design")
[ -n "$missing" ] && bad="${bad}review-design-fix-loop.md Cap-pause: review-planning-update missing parameter(s): $missing; "

cap_article=$(section_between "$LOOP_ARTICLE" '^### Cap-pause' '^### ')
rm_line=$(printf '%s\n' "$cap_article" | $GREP -n 'rm -f /tmp/article-review-todos-before.txt' | head -1 | cut -d: -f1)
rpu_line2=$(printf '%s\n' "$cap_article" | $GREP -n 'review-planning-update/SKILL.md' | head -1 | cut -d: -f1)
if [ -z "$rm_line" ] || [ -z "$rpu_line2" ] || [ "$rm_line" -ge "$rpu_line2" ]; then
    bad="${bad}review-article-fix-loop.md Cap-pause: TODO-snapshot rm does not run before review-planning-update; "
fi
missing=$(rpu_params_missing "$cap_article")
[ -n "$missing" ] && bad="${bad}review-article-fix-loop.md Cap-pause: review-planning-update missing parameter(s): $missing; "

if [ -z "$bad" ]; then
    pass "each loop's ### Cap-pause and ### Stall stop headings exist under the fragment's routed names, and each Cap-pause runs its cleanup before review-planning-update with all five parameters"
else
    fail "each loop's ### Cap-pause and ### Stall stop headings exist under the fragment's routed names, and each Cap-pause runs its cleanup before review-planning-update with all five parameters" "$bad"
fi

# review-design-fix-loop.md only: Step 3 must carry the Draft→Approved header edit, the
# Protocol Deviations status-header bullet must positively name Step 3 as where that edit
# happens (not merely lack one literal negative phrase — a differently-worded prohibition,
# e.g. "must not be set during a re-review pass", still contradicts Step 3 while containing
# neither "never" nor the old wording), and ## Agents must not restate the Steps-1-and-3 set
# a third time.
step3_design=$(section_between "$LOOP_DESIGN" '^### Step 3:' '^### ')
agents_section=$(section_between "$LOOP_DESIGN" '^## Agents' '^## ')
# Scoped to the one bullet, not the whole Protocol Deviations section — "Gate that remains
# active" a few lines down names an unrelated open-questions "prohibition", which a
# section-wide grep for that word would wrongly credit to this bullet.
status_bullet=$($GREP -E '^- \*\*Skip\*\* the design doc status header' "$LOOP_DESIGN")
# The `## Agents` clause for `**Status:**` is checked by what it points AT, not by a list of
# forbidden phrasings it must avoid — "in Step 1 and Step 3" and "in Steps 1, 3" both restate
# the set without matching a `Steps? 1 and (3|4)` literal, so a phrase-list negative lets
# either through. Requiring the clause to name the Protocol Deviations bullet is immune to how
# a restatement is worded, because a genuine pointer is not a restatement of the set at all.
status_agent_clause=$(printf '%s\n' "$agents_section" | $GREP -F '`**Status:**`')
bad=""
printf '%s' "$step3_design" | $GREP -qF '**Status:** Draft' \
    && printf '%s' "$step3_design" | $GREP -qF '**Status:** Approved' \
    || bad="${bad}Step 3 does not carry the Draft to Approved header edit; "
printf '%s' "$status_bullet" | $GREP -qF 'APPROVED row in Step 3' \
    || bad="${bad}Protocol Deviations status-header bullet does not positively name Step 3 as the re-review set-site; "
# A phrase list ('must not be set', 'never...re-review', 'forbid', 'prohibit') is a closed set
# a differently-worded prohibition slips past — "not during a re-review pass" and "except
# during a re-review pass" both forbid the edit without matching any of those four phrases.
# Any negation in the same sentence as "re-review" is the shape of a prohibition regardless
# of its wording; `[^.]*` keeps the match inside one sentence of this unwrapped bullet.
printf '%s' "$status_bullet" \
    | $GREP -qiE '(not|except|never|forbid|prohibit|cannot|no longer)[^.]*re-review|re-review[^.]*(not|except|never|forbid|prohibit|cannot)' \
    && bad="${bad}Protocol Deviations status-header bullet still contains prohibition language for the header edit during re-review; "
printf '%s' "$status_agent_clause" | $GREP -qF 'Protocol Deviations' \
    || bad="${bad}## Agents' \`**Status:**\` clause does not point at the Protocol Deviations bullet; "
if [ -z "$bad" ]; then
    pass "review-design-fix-loop.md: Step 3 sets the header on APPROVED, no re-review prohibition survives under any negation wording, and ## Agents points at the Protocol Deviations bullet instead of restating the step set"
else
    fail "review-design-fix-loop.md: Step 3 sets the header on APPROVED, no re-review prohibition survives under any negation wording, and ## Agents points at the Protocol Deviations bullet instead of restating the step set" "$bad"
fi

# review-iterate.md's Protocol Deviations note must name Steps 1 and 3 — it describes
# /review-design-fix-loop, whose Step 4 no longer exists.
if $GREP -qF 'manages the header transition itself in Steps 1 and 3' "$ITERATE_CMD"; then
    pass "review-iterate.md's Protocol Deviations note names Steps 1 and 3"
else
    fail "review-iterate.md's Protocol Deviations note names Steps 1 and 3" \
         "expected phrase not found — check for a stale 'Steps 1 and 4'"
fi

# Every file in the disclosure set (the fragment and the three fix loops — review-iterate.md
# is exempt) must carry its disclosure sentence, and that sentence — not just the file
# anywhere — must name both suites that parse it. Reading the whole file let an incidental
# mention anywhere stand in for the disclosure; the sentence is a single unwrapped paragraph
# starting "This file is parsed by two tests.", so it is grepped as one line.
bad=""
for f in $FRAGMENT $FIXLOOPS; do
    disclosure=$($GREP -E '^\*\*This file is parsed by two tests\.\*\*' "$f")
    if [ -z "$disclosure" ]; then
        bad="$bad${f#"$CLAUDE_DIR"/}: no disclosure sentence found; "
        continue
    fi
    printf '%s' "$disclosure" | $GREP -qF 'verify-workflow-safety.sh' \
        || bad="$bad${f#"$CLAUDE_DIR"/}: disclosure sentence does not name verify-workflow-safety.sh; "
    printf '%s' "$disclosure" | $GREP -qF 'verify-config-consistency.sh' \
        || bad="$bad${f#"$CLAUDE_DIR"/}: disclosure sentence does not name verify-config-consistency.sh; "
done
if [ -z "$bad" ]; then
    pass "the fragment and all three fix loops carry a disclosure sentence naming both suites that parse them"
else
    fail "the fragment and all three fix loops carry a disclosure sentence naming both suites that parse them" "$bad"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total=$((PASS + FAIL))
if [ "$total" -eq "$EXPECTED_TESTS" ]; then
    pass "all $EXPECTED_TESTS assertions ran"
else
    fail "all $EXPECTED_TESTS assertions ran" \
         "ran $total — a section skipped itself, or EXPECTED_TESTS is stale"
fi

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
