#!/usr/bin/env bash
# verify-comment-gate.sh — fixture suite for platforms/claude/scripts/comment-gate.sh
#
# Every case number below matches planning/genai-automations/mechanism-proportionality/
# step-7-comment-gate/design.md → §6 "Unit Tests". Each fixture builds its own scratch git
# repository: a base commit holds the fixture path's pre-state (empty, unless the case
# needs real content in the base — cases 9, 10, 19-as-context, and 20 do, to exercise the
# working-tree read rather than the added-line stream), and the working tree is then
# overwritten to the case's actual content, so the diff carries exactly the added lines
# the case describes. Cases 7 and 25 are the named exceptions: their fixture path is never
# committed, so the gate measures it through `git ls-files --others` instead of `git diff`.
#
# Runs the full corpus once, then re-runs one representative fixture under every awk on the
# box (gawk and mawk disagree on regex extensions, and /usr/bin/awk is an alternatives
# symlink) — agreement is the property under test there, matching citation-scan's own loop.
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

# The fixed number of assertions run from the top of this file through the end of the
# "present-but-broken awk interpreter" case, i.e. everywhere except the cross-awk loop
# below (whose own count depends on which interpreters the box has installed — see
# AWK_RUNNERS at the loop). A hardcoded floor, matching verify-workflow-safety.sh's and
# verify-config-consistency.sh's EXPECTED_TESTS: update it by hand when a case is added
# or removed above the loop.
BASE_COUNT=187

GREP=/usr/bin/grep
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/platforms/claude/scripts/comment-gate.sh"

TMPDIR_ROOT=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }

echo "comment-gate.sh regression corpus"
echo "script: $SCRIPT"
[ -x "$SCRIPT" ] || { echo "  FAIL: script not executable"; exit 1; }

# --- scratch-repo helpers, one repo per case (or per related case-pair) -------------

CASE_DIR=""

new_repo() {
    CASE_DIR="$TMPDIR_ROOT/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')"
    mkdir -p "$CASE_DIR"
    git -C "$CASE_DIR" init -q
    git -C "$CASE_DIR" config user.email a@b.com
    git -C "$CASE_DIR" config user.name t
}

# commit_file <relpath> — content via stdin (may be empty); adds and commits it, so the
# path is tracked and HEAD resolves.
commit_file() {
    local rel="$1"
    mkdir -p "$(dirname "$CASE_DIR/$rel")"
    cat > "$CASE_DIR/$rel"
    git -C "$CASE_DIR" add "$rel"
    git -C "$CASE_DIR" commit -q -m "base: $rel"
}

# write_file <relpath> — content via stdin; overwrites the working tree only.
write_file() {
    local rel="$1"
    mkdir -p "$(dirname "$CASE_DIR/$rel")"
    cat > "$CASE_DIR/$rel"
}

run_gate() {
    local base="${1:-HEAD}"
    (cd "$CASE_DIR" && bash "$SCRIPT" "$base" 2>&1)
}

# filler <count> <start> — N plain "nK = K" lines, never comment- or declaration-shaped in
# either family, so it is safe generic denominator padding throughout this suite.
filler() {
    local n="$1" start="${2:-1}" i
    for ((i = start; i < start + n; i++)); do
        printf 'n%d = %d\n' "$i" "$i"
    done
}

expected_flag_line() { printf 'flag  %-18s %s:%s' "$1" "$2" "$3"; }

assert_contains() {
    local name="$1" out="$2" want="$3"
    if printf '%s' "$out" | $GREP -qF -- "$want"; then pass "$name"
    else fail "$name" "want to contain: $want"$'\n'"        got: $out"; fi
}

assert_not_contains() {
    local name="$1" out="$2" avoid="$3"
    if printf '%s' "$out" | $GREP -qF -- "$avoid"; then
        fail "$name" "must not contain: $avoid"$'\n'"        got: $out"
    else pass "$name"; fi
}

assert_rc() {
    local name="$1" got="$2" want="$3"
    [ "$got" = "$want" ] && pass "$name" || fail "$name" "want rc=$want got rc=$got"
}

# =====================================================================================
# Case 26 — the five ways the scan does not run at all. Checked first: every other case
# below depends on the happy path these guard around.
# =====================================================================================

# Each assertion below matches its cause's own distinguishing tail, not the bare token
# "BLOCKER" every one of these five paths shares — a bare match lets two guards collapse:
# deleting the no-argument guard or the not-a-repo guard still exits 1 via the
# unresolvable-base branch (an empty/missing BASE_REF fails `git rev-parse --verify`
# too), so only the message text tells the branches apart.
new_repo case26_unresolvable
commit_file f.cc <<< ""
out=$(run_gate "no-such-ref-xyz"); rc=$?
assert_rc "26 unresolvable base ref: exit 1" "$rc" 1
assert_contains "26 unresolvable base ref: names the ref" "$out" "BLOCKER: unresolvable base ref: no-such-ref-xyz"

new_repo case26_noarg
commit_file f.cc <<< ""
out=$(cd "$CASE_DIR" && bash "$SCRIPT" 2>&1); rc=$?
assert_rc "26 no base-ref argument: exit 1" "$rc" 1
assert_contains "26 no base-ref argument: names the missing argument" "$out" "BLOCKER: no <base-ref> argument given"

out=$(cd "$TMPDIR_ROOT" && bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "26 cwd outside any repo: exit 1" "$rc" 1
assert_contains "26 cwd outside any repo: names the missing repo" "$out" "BLOCKER: not a git repository"

new_repo case26_awk_missing
commit_file f.cc <<< ""
out=$(cd "$CASE_DIR" && COMMENT_GATE_AWK=/nonexistent-awk bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "26 nonexistent COMMENT_GATE_AWK: exit 1" "$rc" 1
assert_contains "26 nonexistent COMMENT_GATE_AWK: names the interpreter path" "$out" \
    "BLOCKER: awk interpreter not found: /nonexistent-awk"

NONEXEC="$TMPDIR_ROOT/nonexec-awk"
printf '#!/bin/sh\necho hi\n' > "$NONEXEC"
chmod -x "$NONEXEC"
out=$(cd "$CASE_DIR" && COMMENT_GATE_AWK="$NONEXEC" bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "26 non-executable COMMENT_GATE_AWK: exit 1" "$rc" 1
assert_contains "26 non-executable COMMENT_GATE_AWK: names the interpreter path" "$out" \
    "BLOCKER: awk interpreter not found: $NONEXEC"

# =====================================================================================
# Case 1 — plain baseline: 20 added code lines, no added comments.
# =====================================================================================
new_repo case1
commit_file f.cc <<< ""
write_file f.cc <<EOF
$(filler 20)
EOF
out=$(run_gate)
assert_contains "1 PASS 0% 0/20" "$out" "PASS 0% 0/20"

# =====================================================================================
# Case 2 — 2 comments over 20 code (PASS), then 3 over the same 20 (WARN). Same base,
# working tree evolves between the two runs.
# =====================================================================================
new_repo case2
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n'
    printf '// c1\n// c2\n'
    filler 19 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "2 first state: PASS 10% 2/20" "$out" "PASS 10% 2/20"

{
    printf 'n0 = 0;\n'
    printf '// c1\n// c2\n// c3\n'
    filler 19 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "2 second state: WARN 15% 3/20" "$out" "WARN 15% 3/20"

# =====================================================================================
# Case 3 — 5 comments over 20 code (WARN 25%), then 6 (BLOCK 30%); rc == 0 on the BLOCK.
# =====================================================================================
new_repo case3
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n'
    for i in 1 2 3 4 5; do printf '// c%d\n' "$i"; done
    filler 19 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "3 first state: WARN 25% 5/20" "$out" "WARN 25% 5/20"

{
    printf 'n0 = 0;\n'
    for i in 1 2 3 4 5 6; do printf '// c%d\n' "$i"; done
    filler 19 1
} > "$CASE_DIR/f.cc"
out=$(run_gate); rc=$?
assert_contains "3 second state: BLOCK 30% 6/20" "$out" "BLOCK 30% 6/20"
assert_rc "3 rc == 0 on BLOCK" "$rc" 0

# =====================================================================================
# Case 4 — C-like: 2 body comments plus a 3-line block above `struct Frame {` (keyword
# branch), over 20 added code lines total.
# =====================================================================================
new_repo case4
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n'
    printf '// body A\n// body B\n'
    filler 16 1
    printf '// decl 1\n// decl 2\n// decl 3\n'
    printf 'struct Frame {\n    int x;\n};\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "4 PASS 10% 2/20 (decl block excluded)" "$out" "PASS 10% 2/20"

# =====================================================================================
# Case 5 — the same shape in the Hash family, block above a `def`.
# =====================================================================================
new_repo case5
commit_file f.py <<< ""
{
    printf 'n0 = 0\n'
    printf '# body A\n# body B\n'
    filler 16 1
    printf '# decl 1\n# decl 2\n# decl 3\n'
    printf 'def foo():\n    x = 1\n    return x\n'
} > "$CASE_DIR/f.py"
out=$(run_gate)
assert_contains "5 PASS 10% 2/20 (def excluded)" "$out" "PASS 10% 2/20"

# =====================================================================================
# Case 6 — nine test-head forms, each: declaration/decorator line, one comment, 11 filler
# code lines (den = 12 counting the declaration line itself) -> PASS 0% 0/12.
# =====================================================================================
# Each assertion below pins its own path (as case 17 does for its skip lines): the repo
# accumulates all nine fixtures as uncommitted modifications, so every run_gate call
# re-measures every earlier file too, and a path-free "PASS 0% 0/12" would be satisfied by
# a.go alone regardless of what happens to the other eight is_testdecl() branches.
commit_file a.go <<< ""
{ printf 'func TestX(t *testing.T) {\n// setup\n'; filler 11 1; } > "$CASE_DIR/a.go"
out=$(run_gate); assert_contains "6a func TestX(: PASS 0% 0/12 a.go" "$out" "PASS 0% 0/12 a.go"

commit_file b.py <<< ""
{ printf 'def test_x():\n# setup\n'; filler 11 1; } > "$CASE_DIR/b.py"
out=$(run_gate); assert_contains "6b def test_x(: PASS 0% 0/12 b.py" "$out" "PASS 0% 0/12 b.py"

commit_file c.rs <<< ""
{ printf 'fn test_x() {\n// setup\n'; filler 11 1; } > "$CASE_DIR/c.rs"
out=$(run_gate); assert_contains "6c fn test_x() {: PASS 0% 0/12 c.rs" "$out" "PASS 0% 0/12 c.rs"

commit_file d.cc <<< ""
{ printf 'TEST(Suite, Case) {\n// setup\n'; filler 11 1; } > "$CASE_DIR/d.cc"
out=$(run_gate); assert_contains "6d TEST(: PASS 0% 0/12 d.cc" "$out" "PASS 0% 0/12 d.cc"

commit_file e.cc <<< ""
{ printf 'TEST_F(Suite, Case) {\n// setup\n'; filler 11 1; } > "$CASE_DIR/e.cc"
out=$(run_gate); assert_contains "6e TEST_F(: PASS 0% 0/12 e.cc" "$out" "PASS 0% 0/12 e.cc"

commit_file f.zig <<< ""
{ printf 'test "x" {\n// setup\n'; filler 11 1; } > "$CASE_DIR/f.zig"
out=$(run_gate); assert_contains "6f Zig test \": PASS 0% 0/12 f.zig" "$out" "PASS 0% 0/12 f.zig"

commit_file g.py <<< ""
{ printf '@pytest.mark.slow\n# setup\n@pytest.mark.other\ndef test_y():\n'; filler 9 1; } > "$CASE_DIR/g.py"
out=$(run_gate); assert_contains "6g stacked @pytest decorator: PASS 0% 0/12 g.py" "$out" "PASS 0% 0/12 g.py"

commit_file h.sh <<< ""
{ printf 'test_x() {\n# setup\n'; filler 11 1; } > "$CASE_DIR/h.sh"
out=$(run_gate); assert_contains "6h shell test_x() {: PASS 0% 0/12 h.sh" "$out" "PASS 0% 0/12 h.sh"

commit_file i.sh <<< ""
{ printf '@test "does the thing" {\n# setup\n'; filler 11 1; } > "$CASE_DIR/i.sh"
out=$(run_gate); assert_contains "6i bats @test \": PASS 0% 0/12 i.sh" "$out" "PASS 0% 0/12 i.sh"

# =====================================================================================
# Case 7 — file-head block on a NEW (untracked) file: 2 comments, a blank, 2 more
# comments, then 12 added code lines opening on a plain statement. The ONE case allowed
# to open on its comment block (the file-head class is what is under test).
# =====================================================================================
new_repo case7
commit_file .keep <<< ""
{
    printf '// header 1\n// header 2\n\n// header 3\n// header 4\n'
    filler 12 1
} > "$CASE_DIR/new.cc"
out=$(run_gate)
assert_contains "7 untracked file-head, blank does not split it: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# Case 8 — 2 comments, a blank, then the declaration: the blank breaks adjacency, so the
# block is a body comment.
# =====================================================================================
new_repo case8
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n// comment A\n// comment B\n\nstruct Frame {\n'
    filler 10 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "8 blank breaks adjacency: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# Case 9 — declaration-adjacent, working-tree read: base already carries the declaration,
# only the comment (and unrelated code) is added.
# =====================================================================================
new_repo case9
commit_file f.cc <<EOF
n0 = 0;
struct Frame {
    int x;
};
EOF
{
    printf 'n0 = 0;\n// comment 1\n// comment 2\n// comment 3\nstruct Frame {\n    int x;\n};\n'
    filler 10 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "9 declaration in base, comment added: PASS 0% 0/10" "$out" "PASS 0% 0/10"

# =====================================================================================
# Case 10 — test-head, working-tree read: base already carries the test declaration, only
# the comment (and unrelated code) is added.
# =====================================================================================
new_repo case10
commit_file f.go <<EOF
n0 = 0;
func TestX(t *testing.T) {
}
EOF
{
    printf 'n0 = 0;\nfunc TestX(t *testing.T) {\n// comment 1\n// comment 2\n// comment 3\n}\n'
    filler 10 1
} > "$CASE_DIR/f.go"
out=$(run_gate)
assert_contains "10 test-head in base, comment added: PASS 0% 0/10" "$out" "PASS 0% 0/10"

# =====================================================================================
# Case 11 — `const int kMax = 5;` at indent 2 inside a function body: past indent 0,
# `const` is a block-scope local, not the ambiguous-keyword declaration.
# =====================================================================================
new_repo case11
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\nvoid foo() {\n  // comment A\n  // comment B\n  const int kMax = 5;\n'
    filler 8 1
    printf '}\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "11 indent-2 const is a local: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# Case 12 — `int decode(Frame& f) {` at indent 2 inside `class Decoder {`: the signature
# branch carries no indent bound.
# =====================================================================================
new_repo case12
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\nclass Decoder {\n  // comment A\n  // comment B\n  int decode(Frame& f) {\n'
    filler 7 1
    printf '  }\n};\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "12 signature branch, no indent bound: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# Case 13 — `void foo() {` at indent 0: the plain C-like signature branch.
# =====================================================================================
new_repo case13
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n// comment A\n// comment B\nvoid foo() {\n'
    filler 9 1
    printf '}\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "13 void foo() {: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# Case 14 — shell all-caps `NAME=` at indent 0: the Hash constant branch.
# =====================================================================================
new_repo case14
commit_file f.sh <<< ""
{
    printf 'n0 = 0\n# comment A\n# comment B\nNAME=value\n'
    filler 10 1
} > "$CASE_DIR/f.sh"
out=$(run_gate)
assert_contains "14 shell NAME=: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# The Hash constant branch's PEP-8 spaced form, `NAME = value`: case 14 only pins the
# unspaced shell spelling.
# =====================================================================================
new_repo case_hash_spaced_const
commit_file f.py <<< ""
{
    printf 'n0 = 0\n# comment A\n# comment B\nMAX_SIZE = 10\n'
    filler 10 1
} > "$CASE_DIR/f.py"
out=$(run_gate)
assert_contains "a PEP-8 spaced NAME = form excludes its comment block: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# Case 15 — Hash shell-function branch: `parse_args() {` excludes, a bare `main()` call
# statement (no trailing brace) does not.
# =====================================================================================
new_repo case15a
commit_file f.sh <<< ""
{
    printf 'n0 = 0\n# comment A\n# comment B\nparse_args() {\n'
    filler 10 1
} > "$CASE_DIR/f.sh"
out=$(run_gate)
assert_contains "15a parse_args() {: PASS 0% 0/12" "$out" "PASS 0% 0/12"

new_repo case15b
commit_file f.sh <<< ""
{
    printf 'n0 = 0\n# comment A\n# comment B\nmain()\n'
    filler 10 1
} > "$CASE_DIR/f.sh"
out=$(run_gate)
assert_contains "15b bare main() call: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# Case 16 — 7 body comments, 20 added code lines, 8 added blank lines: blanks stay out of
# the denominator entirely.
# =====================================================================================
new_repo case16
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n'
    for i in 1 2 3 4 5 6 7; do printf '// c%d\n' "$i"; done
    for _ in 1 2 3 4 5 6 7 8; do printf '\n'; done
    filler 19 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "16 blanks excluded from denominator: BLOCK 35% 7/20" "$out" "BLOCK 35% 7/20"

# =====================================================================================
# Case 17 — unknown extensions (.yaml, .md) skip and are unflagged; a .py file measures
# normally alongside them.
# =====================================================================================
new_repo case17
commit_file main.py <<< ""
{ printf 'n0 = 0\n# comment A\n# comment B\n'; filler 19 1; } > "$CASE_DIR/main.py"
commit_file config.yaml <<< ""
printf 'value: 1  # noqa\n' > "$CASE_DIR/config.yaml"
commit_file readme.md <<< ""
printf '# Title\nsome text\n' > "$CASE_DIR/readme.md"
out=$(run_gate)
assert_contains "17 .py measures: PASS 10% 2/20" "$out" "PASS 10% 2/20"
assert_contains "17 .yaml skips" "$out" "skip - - config.yaml (comment syntax unknown)"
assert_contains "17 .md skips" "$out" "skip - - readme.md (comment syntax unknown)"
assert_contains "17 summary: 2 skipped" "$out" "2 skipped"
if printf '%s\n' "$out" | $GREP -q 'flag.*config\.yaml'; then
    fail "17 .yaml's # noqa is unflagged" "found a flag line naming config.yaml :: $out"
else
    pass "17 .yaml's # noqa is unflagged"
fi
assert_not_contains "17 no flag line at all" "$out" "flag  bare-suppression"
assert_rc "17 exit 0" "$(run_gate > /dev/null; echo $?)" 0

# =====================================================================================
# Case 18 — one minimal file per known extension, each opening on a code line, then 2
# body comments over 12 added code lines: WARN on all ten, no skip line.
# =====================================================================================
new_repo case18
for ext in cc cpp h hpp go rs zig; do
    commit_file "f.$ext" <<< ""
    { printf 'n0 = 0;\n// comment A\n// comment B\n'; filler 11 1; } > "$CASE_DIR/f.$ext"
done
for ext in py sh bash; do
    commit_file "f.$ext" <<< ""
    { printf 'n0 = 0\n# comment A\n# comment B\n'; filler 11 1; } > "$CASE_DIR/f.$ext"
done
out=$(run_gate)
n_warn=$(printf '%s\n' "$out" | $GREP -c '^WARN 16% 2/12 ')
[ "$n_warn" = "10" ] && pass "18 all ten extensions WARN 16% 2/12" \
    || fail "18 all ten extensions WARN 16% 2/12" "count=$n_warn :: $out"
assert_not_contains "18 no skip line" "$out" "skip "

# =====================================================================================
# Case 19 — 2 comments over 9 added code lines (small), then over 10 (WARN).
# =====================================================================================
new_repo case19a
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// c1\n// c2\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "19 den=9: small - 2/9" "$out" "small - 2/9"

new_repo case19b
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// c1\n// c2\n'; filler 9 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "19 den=10: WARN 20% 2/10" "$out" "WARN 20% 2/10"

# =====================================================================================
# Case 20 — 3 added comments, zero added code lines: small, no division by zero. The
# declaration/context line is unchanged in the base so the added lines are pure comment.
# =====================================================================================
new_repo case20
commit_file f.cc <<EOF
int existing = 1;
EOF
{ printf 'int existing = 1;\n// comment 1\n// comment 2\n// comment 3\n'; } > "$CASE_DIR/f.cc"
out=$(run_gate); rc=$?
assert_contains "20 small - 3/0" "$out" "small - 3/0"
assert_rc "20 no crash on den=0" "$rc" 0

# =====================================================================================
# Case 21 — a /* … */ span carrying an in-span blank: every non-blank span line counts,
# the blank counts in neither term. The base must have zero lines, not a "<<< \"\"" single
# blank line — git's diff otherwise pairs that blank with the span's own in-span blank as
# unchanged context, so the fixture's blank never enters `added` and the case cannot fail
# against the mutant it names (is_blank(raw) && !in_span) regardless of the guard's fate.
# =====================================================================================
new_repo case21
commit_file f.cc < /dev/null
{
    printf 'n0 = 0;\n/* line1\nline2\nline3\n\nline4\nline5\nline6 */\n'
    filler 19 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "21 in-span blank excluded: BLOCK 30% 6/20" "$out" "BLOCK 30% 6/20"

# =====================================================================================
# Case 22 — a trailing suppression comment on a code line is still a code line, in both
# families.
# =====================================================================================
new_repo case22py
commit_file f.py <<< ""
{
    printf 'n1 = 1  # noqa\n'
    filler 11 2
} > "$CASE_DIR/f.py"
out=$(run_gate)
assert_contains "22 Python trailing # noqa is code: PASS 0% 0/12" "$out" "PASS 0% 0/12"

new_repo case22cc
commit_file f.cc <<< ""
{
    printf 'n1 = 1;  // clamp to the window\n'
    filler 11 2
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "22 C-like trailing // is code: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# Case 23 — bare suppression markers each produce one flag; reasoned forms produce none.
# Plus the second-hunk sub-case, asserted with its true (grep-discovered) line number.
# The comment scoping (STEP-7 design.md §5) added for case 24 below applies to the `TODO`
# grep alone — this grep stays a whole-line scan in both directions, unchanged by it.
# =====================================================================================
new_repo case23py
commit_file flags.py <<< ""
{
    printf 'n1 = 1  # noqa\n'
    printf 'n2 = 2  # type: ignore\n'
    printf 'n3 = 3  # noqa: E501\n'
    printf 'n4 = 4  # noqa: E501 - the URL cannot wrap\n'
} > "$CASE_DIR/flags.py"
out=$(run_gate)
assert_contains "23 bare # noqa" "$out" "$(expected_flag_line bare-suppression flags.py 1)"
assert_contains "23 bare # type: ignore" "$out" "$(expected_flag_line bare-suppression flags.py 2)"
assert_contains "23 rule-code-only # noqa: E501" "$out" "$(expected_flag_line bare-suppression flags.py 3)"
assert_not_contains "23 reasoned # noqa: E501 - ..." "$out" "flags.py:4"

new_repo case23rs
commit_file flags.rs <<< ""
{
    printf 'n1 = 1;  // NOLINT\n'
    printf 'n2 = 2;  // NOLINTNEXTLINE(rule-name)\n'
    printf 'n3 = 3;  //nolint:errcheck\n'
    printf '#[allow(dead_code)]\n'
    printf 'n5 = 5;  // NOLINTNEXTLINE(rule-name): the cast matches the wire format\n'
    printf 'n6 = 6;  //nolint:errcheck // the close is best-effort\n'
} > "$CASE_DIR/flags.rs"
out=$(run_gate)
assert_contains "23 // NOLINT" "$out" "$(expected_flag_line bare-suppression flags.rs 1)"
assert_contains "23 // NOLINTNEXTLINE(rule-name)" "$out" "$(expected_flag_line bare-suppression flags.rs 2)"
assert_contains "23 //nolint:errcheck bare" "$out" "$(expected_flag_line bare-suppression flags.rs 3)"
assert_contains "23 #[allow(dead_code)]" "$out" "$(expected_flag_line bare-suppression flags.rs 4)"
assert_not_contains "23 reasoned NOLINTNEXTLINE(...): ..." "$out" "flags.rs:5"
assert_not_contains "23 reasoned //nolint:errcheck // ..." "$out" "flags.rs:6"

new_repo case23_hunk2
{
    for i in $(seq 1 30); do printf 'old%d = %d\n' "$i" "$i"; done
} > "$TMPDIR_ROOT/case23base.$$"
commit_file wide.cc < "$TMPDIR_ROOT/case23base.$$"
{
    printf 'old1 = 1\nold2 = 2\nextra_top = 1\n'
    for i in $(seq 3 25); do printf 'old%d = %d\n' "$i" "$i"; done
    printf 'flagged = 1  // NOLINT\n'
    for i in $(seq 26 30); do printf 'old%d = %d\n' "$i" "$i"; done
} > "$CASE_DIR/wide.cc"
rm -f "$TMPDIR_ROOT/case23base.$$"
flagged_line=$($GREP -n '^flagged = 1' "$CASE_DIR/wide.cc" | cut -d: -f1)
out=$(run_gate)
assert_contains "23 second-hunk marker keeps its true line number" "$out" \
    "$(expected_flag_line bare-suppression wide.cc "$flagged_line")"

# =====================================================================================
# Case 24 — TODO/FIXME with no ticket flags; one carrying #N or a TICKET-123 token does
# not. Plus a second-hunk sub-case.
# =====================================================================================
new_repo case24
commit_file todos.py <<< ""
{
    printf 'n1 = 1  # TODO\n'
    printf 'n2 = 2  # TODO: HANDLE THE EOF CASE\n'
    printf 'n3 = 3  # TODO(#123)\n'
    printf 'n4 = 4  # TODO(PROJ-12)\n'
    printf 'n5 = 5  # FIXME - see #44\n'
} > "$CASE_DIR/todos.py"
out=$(run_gate)
assert_contains "24 bare TODO" "$out" "$(expected_flag_line todo-no-ticket todos.py 1)"
assert_contains "24 TODO: prose, no ticket" "$out" "$(expected_flag_line todo-no-ticket todos.py 2)"
assert_not_contains "24 TODO(#123) has a ticket" "$out" "todos.py:3"
assert_not_contains "24 TODO(PROJ-12) has a ticket" "$out" "todos.py:4"
assert_not_contains "24 FIXME - see #44 has a ticket" "$out" "todos.py:5"

new_repo case24_hunk2
{
    for i in $(seq 1 30); do printf 'old%d = %d\n' "$i" "$i"; done
} > "$TMPDIR_ROOT/case24base.$$"
commit_file wide.py < "$TMPDIR_ROOT/case24base.$$"
{
    printf 'old1 = 1\nold2 = 2\nextra_top = 1\n'
    for i in $(seq 3 25); do printf 'old%d = %d\n' "$i" "$i"; done
    printf 'flagged = 1  # TODO\n'
    for i in $(seq 26 30); do printf 'old%d = %d\n' "$i" "$i"; done
} > "$CASE_DIR/wide.py"
rm -f "$TMPDIR_ROOT/case24base.$$"
flagged_line=$($GREP -n '^flagged = 1' "$CASE_DIR/wide.py" | cut -d: -f1)
out=$(run_gate)
assert_contains "24 second-hunk TODO keeps its true line number" "$out" \
    "$(expected_flag_line todo-no-ticket wide.py "$flagged_line")"

# =====================================================================================
# Case 24 (comment scoping) — the `TODO` grep now reads only comment text (STEP-7 design.md
# §5 "Why the two differ on comment scope" / observed-failures.md 2026-09-11). Three of the
# four shapes the first real run flagged carry no comment marker at all on a CODE-typed
# line and so are never searched; the fourth — a marker inside a string literal — is the
# named residual (§6 gaps row "Comment markers inside strings") and still flags on purpose.
# =====================================================================================
new_repo case24_scoping
commit_file guard.py <<< ""
{
    printf 'PATTERN = re.compile("(TODO|FIXME)")\n'
    printf 'msg = "TODO: still not a comment"\n'
    printf '# TODO/FIXME with no ticket -- see STEP-7\n'
} > "$CASE_DIR/guard.py"
out=$(run_gate)
assert_not_contains "24 regex literal carrying TODO|FIXME has no marker" "$out" "guard.py:1"
assert_not_contains "24 code line assigning a TODO-carrying string has no marker" "$out" "guard.py:2"
assert_not_contains "24 full-line comment about the rule carries a reference" "$out" "guard.py:3"

new_repo case24_residual
commit_file fixture_data.sh <<< ""
cat > "$CASE_DIR/fixture_data.sh" <<'INNEREOF'
printf 'n1 = 1  # TODO\n'
INNEREOF
out=$(run_gate)
assert_contains "24 TODO inside a string literal is a trailing marker to the gate (residual)" "$out" \
    "$(expected_flag_line todo-no-ticket fixture_data.sh 1)"

# =====================================================================================
# Case 25 — untracked new file, measured whole (C4).
# =====================================================================================
new_repo case25
commit_file .keep <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\n'; filler 11 1; } > "$CASE_DIR/new.cc"
out=$(run_gate)
assert_contains "25 untracked file measured whole: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# Case 27 — control-keyword and bare-call disqualifiers: `if (ready) {` and
# `return compute(x);` are neither declaration-shaped, so both comments count. `if (ready)
# {` alone would not pin is_ctrl_disqualified() — is_signature() already rejects it on its
# own (its remainder ahead of the callee is empty, no type token at all), so deleting the
# disqualifier would not change that verdict. `return compute(x);` closes the gap: its
# remainder ahead of the callee is "return", which looks exactly like a type/qualifier
# token to is_signature()'s terminal-character test, so only is_ctrl_disqualified() stops
# it from reading as a declaration.
# =====================================================================================
new_repo case27
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n// comment A1\n// comment A2\nif (ready) {\n'
    filler 1 1
    printf '}\n// comment B1\n// comment B2\nreturn compute(x);\n'
    filler 7 2
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "27 both disqualifiers: BLOCK 33% 4/12" "$out" "BLOCK 33% 4/12"

# =====================================================================================
# Case 28 — `auto hdr = parse_header(f);`: the token immediately ahead of the callee is
# `=`, not a type, so this is no signature.
# =====================================================================================
new_repo case28
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\nvoid foo() {\n  // comment A\n  // comment B\n  auto hdr = parse_header(f);\n'
    filler 8 1
    printf '}\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "28 auto hdr = parse_header(f); is no signature: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# Case 29 — Go `var count int`: indent 0 excludes (ambiguous keyword), indent 1 (one tab,
# inside a function) does not.
# =====================================================================================
new_repo case29a
commit_file f.go <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nvar count int\n'; filler 10 1; } > "$CASE_DIR/f.go"
out=$(run_gate)
assert_contains "29a indent-0 var: PASS 0% 0/12" "$out" "PASS 0% 0/12"

new_repo case29b
commit_file f.go <<< ""
{
    printf 'n0 = 0;\nfunc foo() {\n\t// comment A\n\t// comment B\n\tvar count int\n'
    filler 8 1
    printf '}\n'
} > "$CASE_DIR/f.go"
out=$(run_gate)
assert_contains "29b one-tab var inside a function: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# Case 30 — 2 comments over 19 added code lines: 10.526 truncates to the 10 the output
# prints, so the verdict stays PASS.
# =====================================================================================
new_repo case30
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// c1\n// c2\n'; filler 18 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "30 truncated 10% stays PASS: PASS 10% 2/19" "$out" "PASS 10% 2/19"

# =====================================================================================
# Case 31 — one run holding a PASS, WARN, BLOCK, small, and skip file, and two flags: the
# whole summary line asserted verbatim.
# =====================================================================================
new_repo case31
commit_file fa.cc <<< ""
filler 20 1 > "$CASE_DIR/fa.cc"

commit_file fb.py <<< ""
{ printf 'n1 = 1  # noqa\n# comment A\n# comment B\n'; filler 11 2; } > "$CASE_DIR/fb.py"

commit_file fc.rs <<< ""
{
    printf 'n0 = 0;\n'
    for i in 1 2 3 4 5 6; do printf '// c%d\n' "$i"; done
    filler 19 1
} > "$CASE_DIR/fc.rs"

commit_file fd.go <<< ""
printf 'n1 = 1\n// TODO\n' > "$CASE_DIR/fd.go"

commit_file fe.yaml <<< ""
printf 'key: value\n' > "$CASE_DIR/fe.yaml"

out=$(run_gate)
# Three flags, not two: fc.rs's six-line body run is also past MAX_COMMENT_RUN, so the
# same fixture that carries the BLOCK ratio carries a long-run flag with it.
assert_contains "31 verbatim summary line" "$out" \
    "comment-gate: 5 files · 1 WARN · 1 BLOCK · 1 small · 1 skipped · 3 flags"
assert_contains "31 the BLOCK file's run also flags as over-long" "$out" \
    "$(expected_flag_line long-comment-run fc.rs 2)"

# =====================================================================================
# is_signature()'s terminal-character test, both directions.
# Positive: a templated/bracketed return type is still a declaration.
# =====================================================================================
new_repo case_m1_pos1
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n// comment A\n// comment B\nstd::optional<Frame> next();\n'
    filler 10 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a templated return type is still a signature: PASS 0% 0/12" "$out" "PASS 0% 0/12"

new_repo case_m1_pos2
commit_file g.cc <<< ""
{
    printf 'n0 = 0;\n// comment A\n// comment B\nstd::vector<std::pair<int,int>> build(int n) {\n'
    filler 10 1
} > "$CASE_DIR/g.cc"
out=$(run_gate)
assert_contains "a nested-template return type is still a signature: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# Negative: a disqualified statement must not read as a declaration.
new_repo case_m1_neg1
commit_file h.cc <<< ""
{
    printf 'n0 = 0;\nvoid foo() {\n  // comment A\n  // comment B\n  throw std::runtime_error("bad frame");\n'
    filler 8 1
    printf '}\n'
} > "$CASE_DIR/h.cc"
out=$(run_gate)
assert_contains "a throw statement is not a declaration: WARN 16% 2/12" "$out" "WARN 16% 2/12"

new_repo case_m1_neg2
commit_file i.cc <<< ""
{
    printf 'n0 = 0;\nvoid foo() {\n  // comment A\n  // comment B\n  auto p = new Frame(x);\n'
    filler 8 1
    printf '}\n'
} > "$CASE_DIR/i.cc"
out=$(run_gate)
assert_contains "an assignment before the callee is not a declaration: WARN 16% 2/12" "$out" "WARN 16% 2/12"

new_repo case_m1_neg3
commit_file j.cc <<< ""
{
    printf 'n0 = 0;\nvoid foo() {\n  if (x) {\n  }\n  // comment A\n  // comment B\n  } else if (ready) {\n'
    filler 5 1
    printf '  }\n}\n'
} > "$CASE_DIR/j.cc"
out=$(run_gate)
assert_contains "a leading-brace else-if is not a declaration: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# HUNK_PARSER must not treat an added line starting with two literal `+` characters (a
# "+++" line once diffed) as the diff's own file-header preamble: swallowing it would
# both drop it from the denominator and shift every later flag's line number.
# =====================================================================================
new_repo case_m2
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n++count;\nflagged = 1;  // NOLINT\n'
    filler 9 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a ++count; line is counted toward the denominator: PASS 0% 0/12 f.cc" "$out" \
    "PASS 0% 0/12 f.cc"
assert_contains "a ++count; line does not shift a later flag's line number" "$out" \
    "$(expected_flag_line bare-suppression f.cc 3)"

# =====================================================================================
# A non-ASCII filename must be measured like any other changed, tracked file, not
# dropped by the readability guard — exercises the `git diff --name-only -z` listing.
# =====================================================================================
new_repo case_m3
commit_file "café.py" <<< ""
{ printf 'n0 = 0\n# comment A\n# comment B\n'; filler 19 1; } > "$CASE_DIR/café.py"
out=$(run_gate)
assert_contains "a non-ASCII tracked filename is measured, not dropped" "$out" "PASS 10% 2/20 café.py"
assert_not_contains "a non-ASCII tracked filename is not reported unreadable" "$out" "café.py (path not readable)"

# =====================================================================================
# The rule-list form of a suppression marker (its OWN grammar, not a reason) must
# still flag: `// NOLINT(rule)`, `# type: ignore[code]`, and bare `// NOLINTNEXTLINE` (no
# parens). `#[allow(dead_code)] // reason` stays a negative — a real reason after it.
# =====================================================================================
new_repo case_m4_rs
commit_file flags2.rs <<< ""
{
    printf 'n1 = 1;  // NOLINT(bugprone-narrowing)\n'
    printf 'n2 = 2;  // NOLINTNEXTLINE\n'
    printf '#[allow(dead_code)] // reason\n'
} > "$CASE_DIR/flags2.rs"
out=$(run_gate)
assert_contains "// NOLINT(rule) flags as bare-suppression" "$out" \
    "$(expected_flag_line bare-suppression flags2.rs 1)"
assert_contains "bare // NOLINTNEXTLINE with no parens flags" "$out" \
    "$(expected_flag_line bare-suppression flags2.rs 2)"
assert_not_contains "#[allow(dead_code)] // reason is not bare" "$out" "flags2.rs:3"

new_repo case_m4_py
commit_file flags2.py <<< ""
printf 'x = 1  # type: ignore[arg-type]\n' > "$CASE_DIR/flags2.py"
out=$(run_gate)
assert_contains "# type: ignore[code] flags as bare-suppression" "$out" \
    "$(expected_flag_line bare-suppression flags2.py 1)"

# =====================================================================================
# A /* ... */ span opened after code on the same line must still type each
# continuation line as a comment, both for the ratio and for the TODO grep (STEP-7
# design.md §5) it feeds.
# =====================================================================================
new_repo case_m5
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\nint x = 5; /* start of a block comment\ncontinued comment line TODO\nstill comment */\n'
    filler 8 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a code-prefixed span opener types its continuation lines as comments" "$out" "WARN 20% 2/10"
assert_contains "a TODO inside a code-prefixed comment span still flags" "$out" "$(expected_flag_line todo-no-ticket f.cc 3)"

# =====================================================================================
# One fixture per declaration token in §5's C-like, indent-0, and Hash keyword lists
# still missing one (struct, var, and def are already pinned elsewhere), plus #define,
# async def, and the indent-0 bound on Hash's NAME= pattern. Table-driven: each row is
# family:construct-line; deleting that token from its matches_any_kw()/starts_kw() list
# turns the comment above the construct from excluded to counted.
# =====================================================================================
new_repo case_m6
m6_rows=(
    "cc:class Foo {"
    "cc:enum Color {"
    "cc:union U {"
    "cc:namespace ns {"
    "cc:template <typename T>"
    "cc:interface Foo {"
    "cc:type Foo = int;"
    "cc:func Foo {"
    "cc:fn foo {"
    "cc:impl Foo {"
    "cc:trait Foo {"
    "cc:mod foo {"
    "cc:pub mod foo {"
    "cc:#define FOO 1"
    "cc:const int kX = 1;"
    "cc:static int gX;"
    "cc:using namespace std;"
    "cc:typedef int MyInt;"
    "cc:constexpr int kX = 1;"
    "py:class Foo:"
    "py:function foo() {"
    "py:readonly x = 1;"
    "py:declare function foo();"
    "py:async def foo():"
)
m6_files=()
m6_lines=()
i=0
for row in "${m6_rows[@]}"; do
    i=$((i + 1))
    ext="${row%%:*}"
    line="${row#*:}"
    fname="m6tok${i}.${ext}"
    commit_file "$fname" <<< ""
    if [ "$ext" = "cc" ]; then
        { printf 'n0 = 0;\n// comment A\n// comment B\n%s\n' "$line"; filler 10 1; } > "$CASE_DIR/$fname"
    else
        { printf 'n0 = 0\n# comment A\n# comment B\n%s\n' "$line"; filler 10 1; } > "$CASE_DIR/$fname"
    fi
    m6_files+=("$fname")
    m6_lines+=("$line")
done
out=$(run_gate)
for idx in "${!m6_files[@]}"; do
    fname="${m6_files[$idx]}"
    line="${m6_lines[$idx]}"
    assert_contains "\`$line\` excludes its preceding comment block: PASS 0% 0/12" "$out" "PASS 0% 0/12 $fname"
done

# The Hash NAME= branch only excludes at indent 0 — indented, it is an ordinary assignment,
# not the ambiguous shell/YAML constant declaration.
commit_file m6_bound.sh <<< ""
{
    printf 'n0 = 0\nif true; then\n  # comment A\n  # comment B\n  NAME=value\n'
    filler 8 1
    printf 'fi\n'
} > "$CASE_DIR/m6_bound.sh"
out=$(run_gate)
assert_contains "an indented NAME= is not excluded (indent-0 bound): WARN 16% 2/12 m6_bound.sh" \
    "$out" "WARN 16% 2/12 m6_bound.sh"

# =====================================================================================
# starts_kw()'s word-boundary test: a keyword prefix must not match without a
# non-identifier character after it. Without the boundary, `publish`/`typedefs`/
# `mod_value` would wrongly match `pub`/`type`/`mod` and their comment blocks would be
# excluded instead of counted.
# =====================================================================================
new_repo case_m9
commit_file pub.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\npublish(x);\n'; filler 10 1; } > "$CASE_DIR/pub.cc"
commit_file typedefs.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\ntypedefs = {};\n'; filler 10 1; } > "$CASE_DIR/typedefs.cc"
commit_file mod.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nmod_value = 1;\n'; filler 10 1; } > "$CASE_DIR/mod.cc"
out=$(run_gate)
assert_contains "publish(x); does not match the keyword pub" "$out" "WARN 16% 2/12 pub.cc"
assert_contains "typedefs = {}; does not match the keyword type/typedef" "$out" "WARN 16% 2/12 typedefs.cc"
assert_contains "mod_value = 1; does not match the keyword mod" "$out" "WARN 16% 2/12 mod.cc"

# =====================================================================================
# FIXME has no positive fixture (STEP-7 design.md §5): narrowing check_todo's matcher to
# /(TODO)/ alone (STEP-7 design.md §5) would leave the suite green without it.
# =====================================================================================
new_repo case_m10
commit_file f.py <<< ""
printf 'n1 = 1  # FIXME\n' > "$CASE_DIR/f.py"
out=$(run_gate)
assert_contains "a bare FIXME flags" "$out" "$(expected_flag_line todo-no-ticket f.py 1)"

# =====================================================================================
# A marker present only in the base, untouched by the diff, must not flag: deleting the
# flag loop's `if (!(i in added)) continue` would flag a legacy TODO (STEP-7 design.md
# §5) on any unrelated edit to the same file.
# =====================================================================================
new_repo case_m11
commit_file f.py <<EOF
n0 = 0  # TODO
EOF
{ printf 'n0 = 0  # TODO\n'; filler 10 1; } > "$CASE_DIR/f.py"
out=$(run_gate)
assert_not_contains "a marker present only in the base is not flagged" "$out" \
    "$(expected_flag_line todo-no-ticket f.py 1)"

# =====================================================================================
# sub(/\r$/, "", raw) strips a trailing CR before any classification; without it a
# trailing marker comment stops matching its own tail grammar. A CRLF file must produce
# the same verdict and the same flag as its LF twin.
# =====================================================================================
new_repo case_m13
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\r\n// comment A\r\n// comment B\r\nflagged = 1;  // NOLINT\r\n'
    filler 10 1 | sed 's/$/\r/'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a CRLF file produces the same verdict as its LF twin: WARN 16% 2/12 f.cc" "$out" "WARN 16% 2/12 f.cc"
assert_contains "a suppression marker with a trailing CR still flags" "$out" \
    "$(expected_flag_line bare-suppression f.cc 4)"

# =====================================================================================
# The deleted-file guard: a tracked file removed from the working tree (uncommitted)
# is reported as an unreadable skip, not silently dropped from N_FILES.
# =====================================================================================
new_repo case_low_deleted
commit_file gone.cc <<EOF
n0 = 0;
EOF
rm -f "$CASE_DIR/gone.cc"
out=$(run_gate)
assert_contains "a deleted tracked file reports skip, not silently dropped" "$out" \
    "skip - - gone.cc (path not readable)"

# =====================================================================================
# comment_marker_pos()'s C-like half: a trailing `// TODO` (STEP-7 design.md §5) and a
# same-line `/* FIXME */` (STEP-7 design.md §5) on otherwise-CODE lines must still be
# found and scanned.
# =====================================================================================
new_repo case_low_marker_pos
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n'
    printf 'flagged1 = 1;  // TODO\n'
    printf 'flagged2 = 2;  /* FIXME */\n'
    filler 8 1
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a trailing // TODO on a code line still flags" "$out" \
    "$(expected_flag_line todo-no-ticket f.cc 2)"
assert_contains "a trailing /* FIXME */ on a code line still flags" "$out" \
    "$(expected_flag_line todo-no-ticket f.cc 3)"

# =====================================================================================
# A POSIX-style space between a shell function name and its parens, `parse_args () {`,
# must still be recognised as a declaration.
# =====================================================================================
new_repo case_low_posix_space
commit_file k.sh <<< ""
{ printf 'n0 = 0\n# comment A\n# comment B\nparse_args () {\n'; filler 10 1; } > "$CASE_DIR/k.sh"
out=$(run_gate)
assert_contains "a POSIX-style space before the parens, parse_args () {, is still a declaration: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# is_signature()'s terminal-character test: a pointer or reference return type, and a
# namespace-qualified callee with no return type at all.
# =====================================================================================
new_repo case_ptr_return
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nFrame* decode(int x);\n'; filler 10 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a pointer return type is still a signature: PASS 0% 0/12" "$out" "PASS 0% 0/12"

new_repo case_ref_return
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nFrame& get(int x);\n'; filler 10 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a reference return type is still a signature: PASS 0% 0/12" "$out" "PASS 0% 0/12"

new_repo case_qualified_call
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nparser::run(x);\n'; filler 10 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a qualified call with no return type is not a signature: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# is_signature()'s trailing `{`/`;` requirement: a constructor init-list continuation
# line ends in `)`, not `{`/`;`, and so is not a declaration on its own.
# =====================================================================================
new_repo case_ctor_initlist
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\nvoid foo() {\n  // comment A\n  // comment B\n  : buffer_(n)\n'
    filler 8 1
    printf '}\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a constructor init-list line ending in ) is not a declaration: WARN 16% 2/12" "$out" "WARN 16% 2/12"

# =====================================================================================
# A one-line /* ... */ that opens and closes on the same physical line must not open a
# span: the following lines stay CODE, in both the line-start and code-prefixed forms.
# =====================================================================================
new_repo case_span_linestart
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n/* note */\n'; filler 11 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a closed one-line /* */ at the start of a line does not swallow the rest of the file: PASS 8% 1/12" "$out" "PASS 8% 1/12"

new_repo case_span_codeprefixed
commit_file f.cc <<< ""
{ printf 'n0 = 0;\nn1 = 1;  /* note */\n'; filler 10 2; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a closed one-line /* */ after code on the same line does not swallow the rest of the file: PASS 0% 0/12" "$out" "PASS 0% 0/12"

# =====================================================================================
# is_blank() must treat a whitespace-only line as blank, not just a zero-length one, so
# it stays out of both the numerator and the denominator.
# =====================================================================================
new_repo case_blank_whitespace
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n// c1\n// c2\n'
    filler 17 1
    printf '   \n   \n   \n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "whitespace-only added lines are excluded from the denominator like empty ones: WARN 11% 2/18" "$out" "WARN 11% 2/18"

# =====================================================================================
# check_bare_suppression()'s NOLINT and type-ignore rows must not flag once a real reason
# follows the marker's own rule-list grammar.
# =====================================================================================
new_repo case_reasoned_nolint
commit_file flags3.rs <<< ""
printf 'n1 = 1;  // NOLINT(rule) - the cast matches the wire format\n' > "$CASE_DIR/flags3.rs"
out=$(run_gate)
assert_not_contains "// NOLINT(rule) followed by a reason is not bare" "$out" "flags3.rs:1"

new_repo case_reasoned_typeignore
commit_file flags3.py <<< ""
printf 'x = 1  # type: ignore[arg-type] - the shim predates strict mode\n' > "$CASE_DIR/flags3.py"
out=$(run_gate)
assert_not_contains "# type: ignore[code] followed by a reason is not bare" "$out" "flags3.py:1"

# =====================================================================================
# A marker's own tail is only ever a colon (no free-text reason after it): the documented
# separator between a marker's rule-list and a reason still counts as "no reason" once
# check_bare_suppression() strips it, both in the C-like and Hash suppression families.
# =====================================================================================
new_repo case_colon_only_tail
commit_file colon_tail.rs <<< ""
{
    printf 'n1 = 1;  // NOLINT(rule):\n'
    printf 'n2 = 2;  // NOLINTNEXTLINE(rule):\n'
} > "$CASE_DIR/colon_tail.rs"
commit_file colon_tail.py <<< ""
{
    printf 'n1 = 1  # type: ignore[arg-type]:\n'
    printf 'n2 = 2  # noqa: E501:\n'
} > "$CASE_DIR/colon_tail.py"
out=$(run_gate)
assert_contains "a // NOLINT(rule): bare trailing colon still flags" "$out" \
    "$(expected_flag_line bare-suppression colon_tail.rs 1)"
assert_contains "a // NOLINTNEXTLINE(rule): bare trailing colon still flags" "$out" \
    "$(expected_flag_line bare-suppression colon_tail.rs 2)"
assert_contains "a # type: ignore[code]: bare trailing colon still flags" "$out" \
    "$(expected_flag_line bare-suppression colon_tail.py 1)"
assert_contains "a # noqa: CODE: bare trailing colon still flags" "$out" \
    "$(expected_flag_line bare-suppression colon_tail.py 2)"

# =====================================================================================
# The classifier-failure guard is a 3-way OR (nonzero exit, empty NUM, empty den), and the
# corpus's own present-but-broken-awk fixture below fires two of its three clauses at once
# (nonzero exit AND empty output), so it cannot tell either clause's own deletion from the
# other's. Each needs a fixture that fires ONLY that clause. The hunk-parser invocation
# still needs a real added-line-number file in both cases (empty would take the unrelated
# "no added lines resolved" skip path instead), so both stubs delegate that one call to
# the real awk and only misbehave for the classifier call, which they recognise by its
# leading -v flag.
# =====================================================================================
new_repo case_awk_silent
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n'; filler 11 1; } > "$CASE_DIR/f.cc"
SILENT_AWK="$TMPDIR_ROOT/silent-awk"
printf '#!/bin/sh\ncase "$1" in\n  -v) exit 0 ;;\n  *) exec awk "$@" ;;\nesac\n' > "$SILENT_AWK"
chmod +x "$SILENT_AWK"
out=$(cd "$CASE_DIR" && COMMENT_GATE_AWK="$SILENT_AWK" bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "a classifier that exits 0 with no output: exit 1" "$rc" 1
assert_not_contains "a classifier that exits 0 with no output: never a clean small - 0/0" "$out" "small - 0/0"

new_repo case_awk_nonzero_with_output
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n'; filler 11 1; } > "$CASE_DIR/f.cc"
FLAKY_AWK="$TMPDIR_ROOT/flaky-awk"
printf '#!/bin/sh\ncase "$1" in\n  -v) printf '"'"'NUM\\t0\\t12\\n'"'"'; exit 1 ;;\n  *) exec awk "$@" ;;\nesac\n' > "$FLAKY_AWK"
chmod +x "$FLAKY_AWK"
out=$(cd "$CASE_DIR" && COMMENT_GATE_AWK="$FLAKY_AWK" bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "a classifier that exits nonzero despite a well-formed NUM line: exit 1" "$rc" 1
assert_not_contains "a classifier that exits nonzero despite a well-formed NUM line: never a clean PASS 0% 0/12" "$out" "PASS 0% 0/12 f.cc"

# =====================================================================================
# The untracked-file listing must measure a non-ASCII filename like any other new file,
# not degrade it to an unreadable skip.
# =====================================================================================
new_repo case_untracked_nonascii
commit_file .keep <<< ""
{ printf 'n0 = 0\n# comment A\n# comment B\n'; filler 11 1; } > "$CASE_DIR/héllo.py"
out=$(run_gate)
assert_contains "an untracked non-ASCII filename is measured, not dropped" "$out" "WARN 16% 2/12 héllo.py"
assert_not_contains "an untracked non-ASCII filename is not reported unreadable" "$out" "héllo.py (path not readable)"

# =====================================================================================
# A newline embedded in an untracked filename must stay one candidate, not split into
# two unreadable fragments.
# =====================================================================================
new_repo case_newline_filename
commit_file .keep <<< ""
newline_name=$'multi\nline.py'
{ printf 'n0 = 0\n# comment A\n# comment B\n'; filler 17 1; } > "$CASE_DIR/$newline_name"
out=$(run_gate)
assert_contains "a filename with an embedded newline is measured as one file" "$out" \
    "comment-gate: 1 files · 1 WARN · 0 BLOCK · 0 small · 0 skipped · 0 flags"
assert_not_contains "a filename with an embedded newline is not reported unreadable" "$out" "path not readable"

# =====================================================================================
# The hunk parser's `\ No newline at end of file` marker must not advance the new-file
# line counter: wrongly counting it as a line shifts every added-line number after it
# out of alignment with the working-tree file, silently dropping the first shifted lines
# from the denominator (PASS 0% 0/10 becomes small - 0/9) even though the flag on the
# fixed marker line happens to still print its true line number by coincidence.
# =====================================================================================
new_repo case_hunk_no_newline
printf 'old1 = 1\nold2 = 2' > "$TMPDIR_ROOT/no-newline-base.$$"
commit_file f.cc < "$TMPDIR_ROOT/no-newline-base.$$"
rm -f "$TMPDIR_ROOT/no-newline-base.$$"
{
    printf 'old1 = 1\nold2 = 2 changed\nflagged = 1;  // NOLINT\n'
    filler 8 1
} > "$CASE_DIR/f.cc"
flagged_line=$($GREP -n '^flagged = 1' "$CASE_DIR/f.cc" | cut -d: -f1)
out=$(run_gate)
assert_contains "a base with no trailing newline does not undercount the denominator: PASS 0% 0/10 f.cc" "$out" \
    "PASS 0% 0/10 f.cc"
assert_contains "a base with no trailing newline does not shift a later flag's line number" "$out" \
    "$(expected_flag_line bare-suppression f.cc "$flagged_line")"

# =====================================================================================
# An awk stub that fails on EVERY invocation — the hunk-parser pipeline AND the untracked
# line-count call, not only the classifier — must still BLOCK. The three existing broken-
# awk stubs (case_awk_silent, case_awk_nonzero_with_output, the cross-awk corpus's
# BROKEN_AWK below) each delegate hunk parsing to the real awk and only misbehave once
# invoked with a leading -v flag, so none of them exercise the PIPESTATUS/total_lines
# guards. f.cc and g.cc stay tracked (committed then modified) to drive the hunk-parser
# PIPESTATUS guard; h.cc is left untracked (never committed) to drive the separate
# line_count_rc/total_lines guard on the untracked-file branch — the case is void of
# coverage for that guard unless at least one of its three fixtures is actually untracked.
# =====================================================================================
new_repo case_awk_fails_everywhere
commit_file f.cc <<< ""
commit_file g.cc <<< ""
printf 'n0 = 0;\nn1 = 1;\n' > "$CASE_DIR/f.cc"
printf 'n0 = 0;\nn1 = 1;\n' > "$CASE_DIR/g.cc"
printf 'n0 = 0;\nn1 = 1;\n' > "$CASE_DIR/h.cc"
out=$(cd "$CASE_DIR" && COMMENT_GATE_AWK=/bin/false bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "an awk that fails on every invocation: exit 1" "$rc" 1
assert_contains "an awk that fails on every invocation: reports BLOCKER on all 3 files" "$out" \
    "BLOCKER: /bin/false failed on 3 file(s) — result is not clean"
assert_not_contains "an awk that fails on every invocation: never a bare skip line" "$out" "skip - -"
assert_not_contains "an awk that fails on every invocation: never a clean small - 0/0" "$out" "small - 0/0"

# =====================================================================================
# A `.gitattributes -diff` path: git reports "Binary files differ" with no `@@` hunks, so
# the hunk-parser awk exits 0 with empty output — the "ran clean, saw zero hunks" shape,
# distinct from case_awk_fails_everywhere's interpreter failure above. It must land on
# `skip - - <f> (no added lines resolved)`, never fall into the small-diff branch as a
# division-by-zero small - 0/0.
# =====================================================================================
new_repo case_binary_no_hunks
commit_file .gitattributes <<< "*.sh -diff"
commit_file f.sh <<< "old content line"
printf 'new content line different entirely\n' > "$CASE_DIR/f.sh"
out=$(run_gate)
assert_contains "a -diff path with no hunks resolves to an explicit skip" "$out" \
    "skip - - f.sh (no added lines resolved)"
assert_not_contains "a -diff path with no hunks never reports small - 0/0" "$out" "small - 0/0"

# =====================================================================================
# A clean tree (no diff, no untracked files) must report zero measured files, not invent a
# skip line from an empty-but-still-executed candidate-file listing. Before the fix,
# printf's format string ran once even with zero file-list operands, emitting one
# NUL-terminated empty record that read as an unreadable path.
# =====================================================================================
new_repo case_clean_tree
commit_file f.cc <<< ""
out=$(run_gate); rc=$?
assert_rc "a clean tree: exit 0" "$rc" 0
assert_contains "a clean tree: verbatim zero-file summary" "$out" \
    "comment-gate: 0 files · 0 WARN · 0 BLOCK · 0 small · 0 skipped · 0 flags"
assert_not_contains "a clean tree: no invented skip line" "$out" "skip - -"

# =====================================================================================
# is_ctrl_disqualified()'s `new`, `co_await`, and `co_return` disqualifiers, plus
# is_signature()'s angle-bracket guard and its `]`/`[` bracketed-return branch — five
# elements with no prior dedicated fixture. The existing `auto p = new Frame(x);` coverage
# (case_m1_neg2) pins the assignment-disqualifier ahead of the callee, not the `new`
# keyword itself: is_signature() already rejects that line on the `=` alone, so deleting
# `new` from the keyword list would not change its verdict. No existing case exercises
# `co_await`/`co_return`, a `>`-terminated remainder with no preceding `<`, or a
# `]`-terminated return type at all.
# =====================================================================================
new_repo case_ctrl_kw_new
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nnew Frame(x);\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a bare placement-new statement is not a declaration: WARN 20% 2/10" "$out" "WARN 20% 2/10"

new_repo case_ctrl_kw_coawait
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nco_await fetch(x);\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a co_await statement is not a declaration: WARN 20% 2/10" "$out" "WARN 20% 2/10"

new_repo case_ctrl_kw_coreturn
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nco_return compute(x);\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a co_return statement is not a declaration: WARN 20% 2/10" "$out" "WARN 20% 2/10"

# `delete X(...);` peels its callee's identifier off the same way `return X(...);` (case 27)
# does, leaving `delete` itself to pass is_signature()'s terminal-character test as if it
# were a return-type token — unlike for/while/switch/catch/do, whose keyword sits directly
# against the `(` and so is already rejected by is_signature() alone.
new_repo case_ctrl_kw_delete
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\ndelete make_frame(x);\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a delete statement is not a declaration: WARN 20% 2/10" "$out" "WARN 20% 2/10"

new_repo case_signature_angle_guard
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nos >> read_value(x);\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a > with no preceding < is not a templated return type: WARN 20% 2/10" "$out" "WARN 20% 2/10"

new_repo case_signature_bracket_return
commit_file f.cc <<< ""
{ printf 'n0 = 0;\n// comment A\n// comment B\nRow[3] decode(int x);\n'; filler 8 1; } > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a bracketed return type is still a signature: PASS 0% 0/10" "$out" "PASS 0% 0/10"

# =====================================================================================
# long-comment-run — a body-comment run past MAX_COMMENT_RUN flags once, at its first
# added line. The excluded classes (file head, declaration-adjacent, test head) are not
# measured, so a long run in any of them stays silent however long it is.
# =====================================================================================
new_repo case_long_run_body
commit_file f.cc <<< ""
{
    printf 'int f() {\n'
    printf '  int a = 1;\n'
    printf '  // run line one\n'
    printf '  // run line two\n'
    printf '  // run line three\n'
    printf '  int b = a;\n'
    printf '  // short one\n'
    printf '  // short two\n'
    printf '  int c = b;\n'
    filler 8 2
    printf '}\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_contains "a three-line body run flags at its first line" "$out" \
    "$(expected_flag_line long-comment-run f.cc 3)"
assert_not_contains "the run flags once, not per line" "$out" "$(expected_flag_line long-comment-run f.cc 4)"
assert_not_contains "a two-line body run is within MAX_COMMENT_RUN" "$out" \
    "$(expected_flag_line long-comment-run f.cc 7)"

new_repo case_long_run_excluded
commit_file f.cc <<< ""
{
    printf '// head one\n// head two\n// head three\n// head four\n'
    printf 'int g();\n'
    printf '// decl one\n// decl two\n// decl three\n// decl four\n'
    printf 'int decode(int x) {\n'
    filler 10 2
    printf '}\n'
} > "$CASE_DIR/f.cc"
out=$(run_gate)
assert_not_contains "a long file-head run is excluded, so unmeasured" "$out" "long-comment-run"

# =====================================================================================
# planning-ref — a comment citing a gitignored planning document or a §N section. Scoped
# to comment text, so the same token as a code operand does not flag.
# =====================================================================================
new_repo case_annotated_const_decl
commit_file f.py <<< ""
{
    printf 'import typing\n'
    printf '\n'
    printf '# Owns the emitted key set for one payload level.\n'
    printf '# A producer test asserts the built dict equals it exactly.\n'
    printf '# A dropped field therefore cannot drift out of the contract.\n'
    printf 'ENVELOPE_FIELDS: typing.Tuple[str, ...] = (\n'
    printf '    "viewer",\n'
    printf ')\n'
    filler 10 2
} > "$CASE_DIR/f.py"
out=$(run_gate)
assert_not_contains "an annotated module-level constant is a declaration" "$out" \
    "$(expected_flag_line long-comment-run f.py 3)"

new_repo case_planning_ref
commit_file f.py <<< ""
{
    printf 'a = 1  # see design.md for the contract\n'
    printf 'b = 2  # per §5.4 of the spec\n'
    printf 'c = 3  # written to planning/foo/bar.md\n'
    printf 'd = 4  # see README.md and CLAUDE.md\n'
    printf 'e = "design.md"\n'
    printf 'f = 6  # section 5.4 of the design\n'
    filler 8 2
} > "$CASE_DIR/f.py"
out=$(run_gate)
assert_contains "a design.md citation flags" "$out" "$(expected_flag_line planning-ref f.py 1)"
assert_contains "a §N section citation flags" "$out" "$(expected_flag_line planning-ref f.py 2)"
assert_contains "a planning/ path citation flags" "$out" "$(expected_flag_line planning-ref f.py 3)"
assert_not_contains "tracked docs are not planning docs" "$out" "$(expected_flag_line planning-ref f.py 4)"
assert_not_contains "a filename as a code operand is not a comment" "$out" "$(expected_flag_line planning-ref f.py 5)"
assert_not_contains "prose naming a section without § does not flag" "$out" "$(expected_flag_line planning-ref f.py 6)"

# =====================================================================================
# Cross-awk agreement: gawk, mawk, awk, busybox-awk must all produce byte-identical
# output for the same corpus, and a substituted broken interpreter must BLOCK rather
# than silently pass. Reuses case 21's span/blank corpus, which exercises the widest
# mix of classification paths (span state, blank-in-span, ratio) in one fixture.
# =====================================================================================
new_repo corpus
commit_file f.cc <<< ""
{
    printf 'n0 = 0;\n/* line1\nline2\nline3\n\nline4\nline5\nline6 */\n'
    filler 19 1
} > "$CASE_DIR/f.cc"

# The required fixture for a classifier that fails outright: COMMENT_GATE_AWK present and
# executable (passes the seam guard's `command -v` check) but broken once invoked — the
# gap case 26's /nonexistent-awk cannot reach, since an absent path never gets past that
# guard at all. The stub delegates the hunk-parser call to the real awk (an empty added-
# line file there takes the unrelated "no added lines resolved" skip path instead of this
# one) and only fails the classifier call, recognised by its leading -v flag.
BROKEN_AWK="$TMPDIR_ROOT/broken-awk"
printf '#!/bin/sh\ncase "$1" in\n  -v) exit 1 ;;\n  *) exec awk "$@" ;;\nesac\n' > "$BROKEN_AWK"
chmod +x "$BROKEN_AWK"
out=$(cd "$CASE_DIR" && COMMENT_GATE_AWK="$BROKEN_AWK" bash "$SCRIPT" HEAD 2>&1); rc=$?
assert_rc "a present-but-broken awk interpreter: exit 1" "$rc" 1
assert_contains "a present-but-broken awk interpreter: reports BLOCKER, not clean" "$out" "BLOCKER"
assert_not_contains "a present-but-broken awk interpreter: never prints small - 0/0" "$out" "small - 0/0"

# BASE_COUNT is the fixed number of assertions run everywhere above this point —
# environment-independent, so (unlike it) hardcoded up top rather than read from the live
# PASS/FAIL counters: reading it from those same counters here would make the floor below
# compare a value against itself, passing trivially even if a whole case block were
# deleted above. The loop's own assertion count is genuinely environment-dependent — one
# per awk interpreter actually found on the box (2 on gawk-only CI, up to 4 with
# mawk/busybox installed too) — so only that part stays computed, added to the hardcoded
# floor below, unlike the sibling suites' single EXPECTED_TESTS constant.
AWK_RUNNERS=0

reference=""
for A in gawk mawk awk busybox-awk; do
    case "$A" in
        busybox-awk)
            command -v busybox >/dev/null 2>&1 || continue
            runner="$TMPDIR_ROOT/busybox-awk"
            printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$runner"
            chmod +x "$runner"
            ;;
        *) command -v "$A" >/dev/null 2>&1 || continue; runner="$A" ;;
    esac
    AWK_RUNNERS=$((AWK_RUNNERS + 1))
    got=$(cd "$CASE_DIR" && COMMENT_GATE_AWK="$runner" bash "$SCRIPT" HEAD 2>&1)
    if [ -z "$reference" ]; then
        reference="$got"; pass "corpus: $A produced a baseline"
    elif [ "$got" = "$reference" ]; then
        pass "corpus: $A agrees with the baseline"
    else
        fail "corpus: $A agrees with the baseline" \
            "$(diff <(printf '%s' "$reference") <(printf '%s' "$got") | head -8)"
    fi
done

if [ "$AWK_RUNNERS" -lt 2 ]; then
    echo "  WARNING: only $AWK_RUNNERS awk runner(s) found on this box — cross-interpreter agreement is undertested"
fi

EXPECTED_TESTS=$((BASE_COUNT + AWK_RUNNERS))
total=$((PASS + FAIL))
if [ "$total" -eq "$EXPECTED_TESTS" ]; then
    pass "all $EXPECTED_TESTS assertions ran ($AWK_RUNNERS awk runner(s) found)"
else
    fail "all $EXPECTED_TESTS assertions ran" \
        "ran $total — a block skipped itself, or the runner count is wrong"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
