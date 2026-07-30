#!/usr/bin/env bash
# verify-citation-scan.sh — regression tests for platforms/claude/scripts/citation-scan.sh
#
# Every case below is a defect that actually occurred during review of the citation rule,
# or a form the rule explicitly permits. See planning/genai-automations/doc-compaction/
# observed-failures.md for the ledger entries these guard.
#
# Runs the whole corpus under every awk on the box (gawk and mawk disagree on interval
# quantifiers, and /usr/bin/awk is an alternatives symlink — so agreement is the property
# under test, not just correctness under one).
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

GREP=/usr/bin/grep
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/platforms/claude/scripts/citation-scan.sh"

TMPDIR_ROOT=$(mktemp -d)
PASS=0
FAIL=0
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }

# assert_class <case-name> <fixture-line> <expected-class|none>
#   Writes the line into a fresh issue folder, scans it, and checks which class came back.
assert_class() {
    local name="$1" body="$2" want="$3" dir out got
    dir="$TMPDIR_ROOT/$(printf '%s' "$name" | tr -c 'a-zA-Z0-9' '_')"
    mkdir -p "$dir"
    printf '%b\n' "$body" > "$dir/design.md"
    # Drop the trailing legend, which names every class and would match all of them.
    out=$(bash "$SCRIPT" "$dir" 2>&1 | $GREP -v '^---')
    if printf '%s' "$out" | $GREP -q 'unpinned source'; then got=unpinned
    elif printf '%s' "$out" | $GREP -q 'planning-doc ref'; then got=planning
    elif printf '%s' "$out" | $GREP -q 'accompanied ok'; then got=accompanied
    elif printf '%s' "$out" | $GREP -q 'WARNING unclosed'; then got=unclosed
    else got=none; fi
    # Reject stray classes too: first-match classification alone would pass a fixture
    # that also emitted an unexpected hit.
    local extra=0
    for c in 'unpinned source' 'planning-doc ref' 'accompanied ok'; do
        case "$want:$c" in
            unpinned:'unpinned source'|planning:'planning-doc ref'|accompanied:'accompanied ok') continue ;;
        esac
        printf '%s' "$out" | $GREP -q "$c" && extra=1
    done
    if [ "$got" = "$want" ] && [ "$extra" = "0" ]; then pass "$name"
    else fail "$name" "want=$want got=$got extra=$extra :: $out"; fi
}

echo "citation-scan.sh regression corpus"
echo "script: $SCRIPT"
[ -x "$SCRIPT" ] || { echo "  FAIL: script not executable"; exit 1; }

# --- input guards: every one of these once reported "clean" ------------------
out=$(bash "$SCRIPT" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q BLOCKER \
    && pass "no argument is a BLOCKER, not clean" \
    || fail "no argument is a BLOCKER, not clean" "rc=$rc out=$out"

out=$(bash "$SCRIPT" 'planning/<NNN-name>' 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'placeholder' \
    && pass "unsubstituted placeholder is a BLOCKER" \
    || fail "unsubstituted placeholder is a BLOCKER" "rc=$rc out=$out"

out=$(bash "$SCRIPT" "$TMPDIR_ROOT/does-not-exist" 2>&1); rc=$?
[ $rc -eq 1 ] && pass "missing directory is a BLOCKER" \
    || fail "missing directory is a BLOCKER" "rc=$rc out=$out"

mkdir -p "$TMPDIR_ROOT/empty"
out=$(bash "$SCRIPT" "$TMPDIR_ROOT/empty" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'no .md files' \
    && pass "directory with no .md is a BLOCKER" \
    || fail "directory with no .md is a BLOCKER" "rc=$rc out=$out"

# --- the rule's three outcomes ----------------------------------------------
assert_class "unpinned source line is flagged"           'see `src/pipeline/pipeline.cc:88`'                 unpinned
assert_class "unpinned range is flagged"                 'see `src/pipeline/pipeline.cc:88-92`'              unpinned
assert_class "pinned source line passes"                 'see `a1b2c3d:src/pipeline/pipeline.cc:88`'         none
assert_class "uppercase pinned hash passes"              'see `A1B2C3D:src/pipeline/pipeline.cc:88`'         none
assert_class "symbol reference passes"                   'see `src/pipeline/pipeline.cc` -> `process_frame`' none
assert_class "bare path passes"                          'see `ci/pipeline.yml`'                             none

# --- planning docs: banned in every form ------------------------------------
assert_class "planning-doc line ref is flagged"          'see `design.md:682-690`'                           planning
assert_class "hash prefix does not license a planning ref" 'see `a1b2c3d:design.md:682-690`'                 planning
assert_class "symbol does not license a planning ref"    'see `design.md:682` \xe2\x86\x92 `foo()`'          planning

# --- accompaniment is permitted ---------------------------------------------
assert_class "line accompanying a symbol is permitted"   'see `src/x.cc:88` \xe2\x86\x92 `process_frame()`'  accompanied

# --- forms that were invisible to earlier versions --------------------------
assert_class "doubled-backtick span is scanned"          'see `` `src/dbl.cc:77` ``'                         unpinned
assert_class "unbackticked locator is scanned"           '**Location:** src/unb.cc:88-92'                    unpinned
assert_class "locator mid-span is scanned"               'see `src/mid.cc:88 (in process_frame)`'            unpinned
assert_class "Makefile target is scanned"                'see `Makefile:42`'                                 unpinned
assert_class "lowercase dockerfile is scanned"           'see `dockerfile:7`'                                unpinned
assert_class "typescript path is scanned"                'see `web/app.ts:44`'                               unpinned
assert_class "toml path is scanned"                      'see `Cargo.toml:11`'                               unpinned

# --- permalinks: pinned passes, branch refs do not --------------------------
assert_class "hash-pinned permalink passes" \
    'x [`src/t.rs:40-53`](https://github.com/o/r/blob/a1b2c3d4e5f6/src/t.rs#L40-L53)'  none
assert_class "branch permalink is flagged" \
    'x [`src/b.rs:3-4`](https://github.com/o/r/blob/dev/src/b.rs#L3-L4)'               unpinned
assert_class "hex-word branch permalink is flagged" \
    'x [`src/e.rs:9`](https://github.com/o/r/blob/cafe/src/e.rs#L9)'                   unpinned

# --- non-locators must not be flagged ---------------------------------------
assert_class "scheme URL with port passes"               'see `http://host:8080`'                            none
assert_class "clock time passes"                         'at `10:30` today'                                  none
assert_class "prose ratio passes"                        'a `3.5:1` ratio'                                   none

# --- fences ------------------------------------------------------------------
assert_class "fenced output is exempt" \
    'x\n```\nsrc/fenced.cc:12\n```'                                                    none
assert_class "content after a closed fence is scanned" \
    'x\n```\ny\n```\nsee `src/after.cc:5`'                                             unpinned
assert_class "nested fence inside a ledger block stays exempt" \
    'x\n~~~markdown\n## 2026-07-30 boom\n```\nsrc/nested.cc:2\n```\n~~~'               none
assert_class "unclosed fence warns instead of reporting clean" \
    'x\n```\nsrc/runaway.cc:99'                                                        unclosed

# --- file-shape edge cases ---------------------------------------------------
crlf="$TMPDIR_ROOT/crlf"; mkdir -p "$crlf"
printf 'see `src/crlf.cc:88`\r\n' > "$crlf/design.md"
bash "$SCRIPT" "$crlf" 2>&1 | $GREP -q 'unpinned source' \
    && pass "CRLF line endings are scanned" \
    || fail "CRLF line endings are scanned" "$(bash "$SCRIPT" "$crlf" 2>&1)"

nonl="$TMPDIR_ROOT/nonl"; mkdir -p "$nonl"
printf 'see `src/nonl.cc:88`' > "$nonl/design.md"
bash "$SCRIPT" "$nonl" 2>&1 | $GREP -q 'unpinned source' \
    && pass "file without trailing newline is scanned" \
    || fail "file without trailing newline is scanned" "$(bash "$SCRIPT" "$nonl" 2>&1)"

# --- mixed line: the whole-line-filter defect (ledger entry 5) ---------------
# A line carrying a pinned and an unpinned locator must report exactly one hit, the
# unpinned one. Filtering by line instead of by token dropped both. Asserted by count,
# not by class, because assert_class stops at its first match and would pass either way.
mixed="$TMPDIR_ROOT/mixed"; mkdir -p "$mixed"
printf 'pinned `a1b2c3d:src/a.cc:10` and unpinned `src/b.cc:214` together\n' > "$mixed/design.md"
got=$(bash "$SCRIPT" "$mixed" 2>&1 | $GREP -v '^---')
n=$(printf '%s\n' "$got" | $GREP -c 'src/' || true)
if [ "$n" = "1" ] && printf '%s' "$got" | $GREP -q 'unpinned source   src/b.cc:214'; then
    pass "mixed line reports exactly the unpinned locator"
else
    fail "mixed line reports exactly the unpinned locator" "hits=$n :: $got"
fi

# --- awk agreement: the property that broke under mawk -----------------------
corpus="$TMPDIR_ROOT/corpus"; mkdir -p "$corpus"
cat > "$corpus/design.md" <<'FIXTURE'
unpinned `src/a.cc:1`
pinned `a1b2c3d:src/b.cc:2`
planning `design.md:3`
permalink [`src/c.rs:4`](https://github.com/o/r/blob/a1b2c3d4e5f6/src/c.rs#L4)
branch [`src/d.rs:5`](https://github.com/o/r/blob/dev/src/d.rs#L5)
accompanied `src/e.cc:6` → `run()`
FIXTURE
# Guard: prove the seam is honoured before trusting any agreement result. A substitution
# that silently fails would run one awk four times and report four vacuous passes.
out=$(CITATION_SCAN_AWK=/nonexistent-awk bash "$SCRIPT" "$corpus" 2>&1); rc=$?
if [ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'BLOCKER'; then
    pass "a broken awk is a BLOCKER, not clean"
else
    fail "a broken awk is a BLOCKER, not clean" "rc=$rc out=$out"
fi

reference=""
for A in gawk mawk awk busybox-awk; do
    case "$A" in
        busybox-awk)
            command -v busybox >/dev/null 2>&1 || continue
            # A two-word interpreter cannot resolve as one command, so wrap it.
            runner="$TMPDIR_ROOT/busybox-awk"
            printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$runner"
            chmod +x "$runner" ;;
        *) command -v "$A" >/dev/null 2>&1 || continue; runner="$A" ;;
    esac
    got=$(CITATION_SCAN_AWK="$runner" bash "$SCRIPT" "$corpus" 2>&1)
    if [ -z "$reference" ]; then
        reference="$got"; pass "$A produced a baseline"
    elif [ "$got" = "$reference" ]; then
        pass "$A agrees with the baseline"
    else
        fail "$A agrees with the baseline" "$(diff <(printf '%s' "$reference") <(printf '%s' "$got") | head -8)"
    fi
done

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
