#!/usr/bin/env bash
# verify-doc-metrics.sh — regression tests for platforms/claude/scripts/doc-metrics.sh
#
# The measurement claims are what is under test: prose words means words outside fences,
# tables, and headings; register matching is whole-word with mention exemptions; a run that
# cannot be trusted BLOCKS rather than reporting a number; and every awk on the box produces
# byte-identical output.
#
# Every assertion here was checked by breaking the behaviour it targets and confirming it
# goes red. Two earlier versions of this suite passed vacuously — see the ledger entries in
# planning/genai-automations/doc-compaction/observed-failures.md. The recurring shape is an
# assertion that matches something other than what it names, so assertions below prefer
# exact field reads and whole-line shapes over substring greps.
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

GREP=/usr/bin/grep
AWKBIN=/usr/bin/awk
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/platforms/claude/scripts/doc-metrics.sh"
AGENT_DOC="$(cd "$(dirname "$0")/.." && pwd)/platforms/claude/agents/architecture-research-planner.md"
CODEX_DOC="$(cd "$(dirname "$0")/.." && pwd)/platforms/codex/skills/architecture-research-planner/SKILL.md"

# Bump when adding or removing a test. Asserted at the end so a block that silently skips
# itself — as the interpreter loop once did on a one-awk box — shows up as a count mismatch
# instead of a green run.
EXPECTED_TESTS=254

TMPDIR_ROOT=$(mktemp -d)
PASS=0
FAIL=0
SKIP=0
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }
fail() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }

# doc <name> <body> — write a fixture, echo its path.
doc() {
    local path
    path="$TMPDIR_ROOT/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_').md"
    printf '%b\n' "$2" > "$path"
    printf '%s' "$path"
}

# field <output> <section-label> <col>   col: 1=words 2=share 3=reg 4=target 5=ceiling 6=verdict
#   Splits on tab and matches the label EXACTLY. An earlier version interpolated the label
#   into a grep BRE, so the `.` in "5. Detailed Design" matched "5x Detailed Design" and the
#   read silently returned another row's number.
field() {
    printf '%s\n' "$1" | $AWKBIN -F'\t' -v lbl="$2" -v c="$3" '
      { n = $1; sub(/[ \t]+$/, "", n)
        if (n == lbl) { v = $(c + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit } }'
}

# summary <output> <REGISTER|CEILING>
summary() { printf '%s\n' "$1" | $GREP -m 1 "^$2:" | $AWKBIN '{print $2}'; }

# assert_total <case> <body> <want-words> <want-register>
assert_total() {
    local name="$1" body="$2" ww="$3" wr="$4" path out gw gr
    path=$(doc "$name" "$body")
    out=$(bash "$SCRIPT" "$path" 2>&1)
    gw=$(field "$out" TOTAL 1)
    gr=$(summary "$out" REGISTER)
    if [ "$gw" = "$ww" ] && [ "$gr" = "$wr" ]; then pass "$name"
    else fail "$name" "want words=$ww register=$wr, got words=$gw register=$gr :: $out"; fi
}

# assert_blocks <case> <expected-message-fragment> <args...>
assert_blocks() {
    local name="$1" frag="$2"; shift 2
    local out rc
    out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | $GREP -qF "$frag"; then pass "$name"
    else fail "$name" "rc=$rc want-fragment='$frag' out=$out"; fi
}

echo "doc-metrics.sh regression corpus"
echo "script: $SCRIPT"
[ -x "$SCRIPT" ] || { echo "  FAIL: script not executable"; exit 1; }

# --- input guards. Each asserts its OWN message, so deleting one guard cannot be masked
# --- by a different guard also returning 1.
assert_blocks "no argument BLOCKs"            "BLOCKER: no file given"
assert_blocks "placeholder path BLOCKs"       "BLOCKER: placeholder left in path" 'planning/<NNN>/design.md'
assert_blocks "missing file BLOCKs"           "BLOCKER: not a file" "$TMPDIR_ROOT/missing.md"
assert_blocks "directory argument BLOCKs"     "BLOCKER: not a file" "$TMPDIR_ROOT"

path=$(doc guard 'one two three')
out=$(DOC_METRICS_AWK=/nonexistent-awk bash "$SCRIPT" "$path" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'BLOCKER: awk interpreter not found' \
    && pass "absent awk BLOCKs with its own message" \
    || fail "absent awk BLOCKs with its own message" "rc=$rc out=$out"

# An interpreter that exists and exits 0 without emitting a table has measured nothing.
# `command -v` cannot catch this, and the AWK_STATUS exit check cannot either.
for stub in /bin/true /bin/echo; do
    out=$(DOC_METRICS_AWK=$stub bash "$SCRIPT" "$path" 2>&1); rc=$?
    [ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'no usable measurement' \
        && pass "awk stand-in $stub BLOCKs (no table emitted)" \
        || fail "awk stand-in $stub BLOCKs (no table emitted)" "rc=$rc out=$out"
done

# An awk that exists and FAILS at runtime. The only previous awk-failure case hit the
# command -v guard, so the per-file failure path was individually deletable.
badawk="$TMPDIR_ROOT/badawk"; printf '#!/bin/sh\nexit 3\n' > "$badawk"; chmod +x "$badawk"
out=$(DOC_METRICS_AWK="$badawk" bash "$SCRIPT" "$path" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'no usable measurement' \
    && pass "awk failing at runtime BLOCKs" \
    || fail "awk failing at runtime BLOCKs" "rc=$rc out=$out"

nulf="$TMPDIR_ROOT/nul.md"; printf 'alpha beta deliberately\000gamma by design\n' > "$nulf"
assert_blocks "NUL bytes BLOCK" "BLOCKER: NUL bytes" "$nulf"

# --- what counts as a prose word ---------------------------------------------
assert_total "plain words are counted"              'one two three'                  3 0
assert_total "punctuation-only tokens do not count" 'one \xe2\x80\x94 two'           2 0
assert_total "bold markup does not add words"       '**one** two'                    2 0
assert_total "inline code without spaces is one word" 'call `process_frame()` now'   3 0
assert_total "list marker is not a word"            '- one two'                      2 0
assert_total "ordered list marker is not a word"    '1. one two'                     2 0
assert_total "blank lines contribute nothing"       'one\n\ntwo'                     2 0
assert_total "CJK words are counted"                '\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e \xe3\x81\xae\xe3\x83\x86\xe3\x82\xad\xe3\x82\xb9\xe3\x83\x88' 2 0
assert_total "Cyrillic words are counted"           '\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82 \xd0\xbc\xd0\xb8\xd1\x80' 2 0

# --- exclusions ---------------------------------------------------------------
assert_total "fenced content is excluded"        'one\n```\nalpha beta gamma\n```\ntwo'     2 0
assert_total "tilde fence is excluded"           'one\n~~~\nalpha beta\n~~~\ntwo'           2 0
assert_total "nested fence stays excluded"       'one\n~~~markdown\n## x\n```\na b\n```\n~~~\ntwo' 2 0
assert_total "four-backtick fence is not closed by three" \
    'one\n````\nalpha ```beta``` gamma\n```\ndelta epsilon\n````\ntwo'                      2 0
assert_total "info-string line does not close a fence" \
    'one\n```\nalpha\n```yaml\nbeta\n```\ntwo'                                             2 0
assert_total "fence inside a blockquote is a fence" \
    'one\n> ```\n> alpha beta\n> ```\ntwo'                                                 2 0
assert_total "table cells count at half weight"    'one\n| a | b |\n| - | - |\ntwo'        3 0
assert_total "indented table cells count at half"  'one\n  | a | b |\ntwo'                 3 0
# The evasion this weight exists to stop: wrapping prose in pipes must not zero a section.
assert_total "pipe-wrapped prose still counts"     '| alpha beta gamma delta | x |'         2 0
assert_total "heading text is excluded from words" '## 1. Problem Statement\none two'       2 0
assert_total "deep heading text is excluded"       '### Goals\none two'                     2 0

# --- register detection -------------------------------------------------------
assert_total "single-word register token counts"    'the queue is deliberately unbounded'   5 1
assert_total "register match is case-insensitive"   'Deliberately unbounded'                2 1
assert_total "multi-word register token counts"     'this is by design here'                5 1
assert_total "four-word register token counts"      'which is what makes it safe'           6 1
assert_total "two hits on one line both count"      'deliberately and intentionally so'     4 2
assert_total "repeated token counts each time"      'deliberately here and deliberately there' 5 2
assert_total "substring is not a hit"               'the design is sound'                   4 0
assert_total "important is not importantly"         'an important constraint'               3 0

# Negative cases for the multi-word matcher. Reducing the comparison to its first word
# leaves the positive cases above green, so these carry the whole contract.
assert_total "by the design is not by design"       'by the design here'                    4 0
assert_total "which is not what makes is not a hit" 'which is not what makes it'            6 0
assert_total "that was said is not that said"       'that was said clearly'                 4 0
assert_total "in a few other words is not a hit"    'in a few other words'                  5 0
assert_total "of the course is not of course"       'of the course'                         3 0

# --- register scope: fences exempt, everything else counted -------------------
assert_total "register inside a fence is exempt"    'a\n```\ndeliberately\n```\nb'          2 0
assert_total "register in a table cell counts"      '| deliberately | x |'                  1 1
assert_total "register in a blockquote counts"      '> the ticket says deliberately'        4 1
assert_total "register in a heading counts"         '## 5. Detailed Design deliberately so\nalpha' 1 1

# --- mention exemption: the token named, not used ----------------------------
assert_total "backticked token is a mention"        'the word `deliberately` is banned'     5 0
assert_total "quoted token is a mention"            'sixteen uses of "deliberately".'       4 0
assert_total "bold-quoted token is a mention"       'see **`by design`** below'             4 0
assert_total "backticked multi-word is a mention"   'the phrase `which is what makes` here' 7 0
assert_total "single-quoted token is a mention"     "use 'deliberately' there"              3 0
assert_total "token in a wider code span is a mention" 'run `grep -x '"'"'deliberately|.*'"'"'` now' 5 0
# The span opens on an earlier word, so the token only CLOSES it and its first character is
# an ordinary letter — the symmetric quote test alone cannot see this.
assert_total "a token closing a code span is a mention" 'see `the queue is deliberately` here' 6 0
# Head and tail must be stripped symmetrically. Stripping only *_ from the head made a
# parenthesised mention a violation while the same token before a `)` was exempt.
assert_total "parenthesised mention is exempt"      'see ("deliberately") above'            3 0
assert_total "two parenthesised mentions both exempt" 'tokens ("note that", "of course") here' 6 0
assert_total "bracketed mention is exempt"          '["deliberately"] in brackets'          3 0
assert_total "em-dash-glued mention is exempt"      '\xe2\x80\x94"deliberately" em dash'    3 0
assert_total "curly double quotes are a mention"    'the term \xe2\x80\x9cdeliberately\xe2\x80\x9d here' 4 0
assert_total "curly single quotes are a mention"    'the term \xe2\x80\x98deliberately\xe2\x80\x99 here' 4 0
assert_total "guillemets are a mention"             '\xc2\xabdeliberately\xc2\xbb guillemets' 2 0
assert_total "german quotes are a mention"          '\xe2\x80\x9edeliberately\xe2\x80\x9c german' 2 0
assert_total "token inside a quoted sentence is a use" '"the queue is deliberately unbounded"' 5 1

# --- sections -----------------------------------------------------------------
path=$(doc sections '**Goal:** g\n\n## 1. Problem Statement\n\nalpha beta\n\n## 5. Detailed Design\n\ngamma delta epsilon deliberately')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '(preamble)' 1)" = "2" ] \
    && [ "$(field "$out" '1. Problem Statement' 1)" = "2" ] \
    && [ "$(field "$out" '5. Detailed Design' 1)" = "4" ] \
    && [ "$(field "$out" '5. Detailed Design' 3)" = "1" ] \
    && [ "$(field "$out" '1. Problem Statement' 3)" = "0" ] \
    && pass "words and register attribute to the enclosing section" \
    || fail "words and register attribute to the enclosing section" "$out"

# An H1 mid-document must close the enclosing H2. Without this, prose under it was
# attributed to the previous ## and real config files reported one section holding four.
path=$(doc midh1 '## Section A\nalpha beta\n# Top Level Two\ngamma delta epsilon\n## Section B\nzeta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" 'Section A' 1)" = "2" ] && [ "$(field "$out" 'Top Level Two' 1)" = "3" ] \
    && [ "$(field "$out" 'Section B' 1)" = "1" ] \
    && pass "a mid-document H1 opens its own section" \
    || fail "a mid-document H1 opens its own section" "$out"

# ### rolls up into its ## parent — a documented contract with no assertion before.
path=$(doc rollup '## 5. Detailed Design\nalpha beta\n### Sub-heading\ngamma delta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '5. Detailed Design' 1)" = "4" ] && [ -z "$(field "$out" 'Sub-heading' 1)" ] \
    && pass "a level-3 heading rolls up into its parent" \
    || fail "a level-3 heading rolls up into its parent" "$out"

path=$(doc emptysection '## 2. Goals and Non-Goals\n\n## 5. Detailed Design\n\nalpha')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '2. Goals and Non-Goals' 1)" = "0" ] \
    && pass "a declared section with no prose reports zero" \
    || fail "a declared section with no prose reports zero" "$out"

path=$(doc nopreamble '## 5. Detailed Design\n\nalpha')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ -z "$(field "$out" '(preamble)' 1)" ] \
    && pass "an absent preamble adds no row" \
    || fail "an absent preamble adds no row" "$out"

# Section rows must appear in document order; reversing the insertion order once left the
# whole suite green because every assertion grepped rows individually.
path=$(doc order '## Alpha\na\n## Beta\nb\n## Gamma\nc')
out=$(bash "$SCRIPT" "$path" 2>&1)
got=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '$1 ~ /^(Alpha|Beta|Gamma)/ {n=$1; sub(/[ \t]+$/,"",n); printf "%s ", n}')
[ "$got" = "Alpha Beta Gamma " ] \
    && pass "section rows follow document order" \
    || fail "section rows follow document order" "got='$got' :: $out"

path=$(doc dupname '## Notes\nalpha\n## 5. Detailed Design\nbeta\n## Notes\ngamma delta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" 'Notes' 1)" = "1" ] && [ "$(field "$out" 'Notes (2)' 1)" = "2" ] \
    && pass "a repeated heading gets its own row" \
    || fail "a repeated heading gets its own row" "$out"

path=$(doc closehash '## 5. Detailed Design ##\nalpha')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '5. Detailed Design' 1)" = "1" ] \
    && pass "closing-hash headings normalise to the same name" \
    || fail "closing-hash headings normalise to the same name" "$out"

# --- targets, ceilings, verdicts ----------------------------------------------
path=$(doc verdict_ok '## 1. Problem Statement\nalpha beta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '1. Problem Statement' 4)" = "184" ] \
    && [ "$(field "$out" '1. Problem Statement' 5)" = "-" ] \
    && [ "$(field "$out" '1. Problem Statement' 6)" = "ok" ] \
    && [ "$(summary "$out" CEILING)" = "0" ] \
    && pass "an uncapped section shows its target and a dash ceiling" \
    || fail "an uncapped section shows its target and a dash ceiling" "$out"

# 210 words: over the 184 target, under the 207 ceiling.
body='## 1. Problem Statement\n'; i=0
while [ $i -lt 190 ]; do body="${body}word "; i=$((i+1)); done
path=$(doc verdict_over "$body")
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '1. Problem Statement' 6)" = "over-target" ] && [ "$(summary "$out" CEILING)" = "0" ] \
    && pass "over target but under ceiling is over-target, not counted by CEILING" \
    || fail "over target but under ceiling is over-target, not counted by CEILING" "$out"

# Uncapped slots never reach OVER-CEILING however large they get.
body='## 1. Problem Statement\n'; i=0
while [ $i -lt 400 ]; do body="${body}word "; i=$((i+1)); done
path=$(doc verdict_nocap "$body")
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '1. Problem Statement' 6)" = "over-target" ] && [ "$(summary "$out" CEILING)" = "0" ] \
    && pass "an uncapped section never blocks however large" \
    || fail "an uncapped section never blocks however large" "$out"

# Slot 6 is capped at 1515.
body='## 6. Test Requirements\n'; i=0
while [ $i -lt 1800 ]; do body="${body}word "; i=$((i+1)); done
path=$(doc verdict_cap6 "$body")
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '6. Test Requirements' 5)" = "1754" ] \
    && [ "$(field "$out" '6. Test Requirements' 6)" = "OVER-CEILING" ] \
    && [ "$(summary "$out" CEILING)" = "1" ] \
    && pass "a capped section over its ceiling blocks" \
    || fail "a capped section over its ceiling blocks" "$out"

# A slot spanning several rows shows its accumulated total beside the ceiling, or a
# zero-word row reads OVER-CEILING with nothing on the line to explain it.
path=$(doc slottotal '## 6. Test Requirements\nalpha beta\n\n## 1. Problem Statement\ngamma\n\n## 6. Tests again\ndelta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '6. Test Requirements' 5)" = "3/1754" ] \
    && [ "$(field "$out" '1. Problem Statement' 5)" = "-" ] \
    && pass "a multi-row slot shows its accumulated total beside the ceiling" \
    || fail "a multi-row slot shows its accumulated total beside the ceiling" "$out"

# The ceiling is per SLOT, not per row: splitting or repeating a heading must not
# multiply the budget. 900 + 900 exceeds slot 6's 1515 while neither row does alone.
body='## 6. Test Requirements\n'; i=0
while [ $i -lt 1000 ]; do body="${body}word "; i=$((i+1)); done
body="${body}\n\n## 6. Test Requirements — Part B\n"; i=0
while [ $i -lt 1000 ]; do body="${body}word "; i=$((i+1)); done
path=$(doc slotsplit "$body")
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(summary "$out" CEILING)" = "1" ] \
    && pass "splitting a capped section does not multiply its budget" \
    || fail "splitting a capped section does not multiply its budget" "$out"

# The document ceiling is asserted directly; nothing else reads TOTAL columns 4-6.
body=''; i=0
while [ $i -lt 8400 ]; do body="${body}word "; i=$((i+1)); done
path=$(doc docceil "$body")
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" TOTAL 4)" = "5800" ] && [ "$(field "$out" TOTAL 5)" = "8322" ] \
    && [ "$(field "$out" TOTAL 6)" = "OVER-CEILING" ] && [ "$(summary "$out" CEILING)" = "1" ] \
    && pass "the document ceiling blocks and is reported on the TOTAL row" \
    || fail "the document ceiling blocks and is reported on the TOTAL row" "$out"

# Older documents number Trade-offs §6 and Open Questions §7; the target must match on
# content, not on the number, or the check silently compares nothing.
path=$(doc canon7 '## 6. Trade-offs and Alternatives\nalpha')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '6. Trade-offs and Alternatives' 4)" = "580" ] \
    && pass "a 7-section-template heading matches its target by content" \
    || fail "a 7-section-template heading matches its target by content" "$out"

path=$(doc nontarget '## Appendix B\nalpha')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" 'Appendix B' 4)" = "-" ] && [ "$(field "$out" 'Appendix B' 6)" = "-" ] \
    && pass "a section with no target reads - rather than 0" \
    || fail "a section with no target reads - rather than 0" "$out"

# --- share --------------------------------------------------------------------
path=$(doc share '## A\n\nalpha\n\n## B\n\nbeta gamma delta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" A 2)" = "25.0%" ] && [ "$(field "$out" B 2)" = "75.0%" ] \
    && pass "share is a percentage of the prose total" \
    || fail "share is a percentage of the prose total" "$out"

# A zero-total document must still emit readable columns. Blanking this branch reproduced
# the collapsed-column defect and no assertion noticed.
path=$(doc zerototal '## 2. Goals and Non-Goals')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '2. Goals and Non-Goals' 1)" = "0" ] \
    && [ "$(field "$out" '2. Goals and Non-Goals' 2)" = "-" ] \
    && [ "$(field "$out" TOTAL 1)" = "0" ] \
    && pass "a zero-total document keeps its columns readable" \
    || fail "a zero-total document keeps its columns readable" "$out"

# --- file shape ---------------------------------------------------------------
nonl="$TMPDIR_ROOT/nonl.md"; printf 'one two three' > "$nonl"
out=$(bash "$SCRIPT" "$nonl" 2>&1)
[ "$(field "$out" TOTAL 1)" = "3" ] \
    && pass "file without trailing newline is counted" \
    || fail "file without trailing newline is counted" "$out"

# The CR strip is load-bearing for the section NAME, not the count — normalisation drops a
# stray CR from a word anyway, so a count-only assertion cannot see the strip.
crlf="$TMPDIR_ROOT/crlf.md"; printf '## 1. Problem Statement\r\none deliberately two\r\n' > "$crlf"
out=$(bash "$SCRIPT" "$crlf" 2>&1)
if [ "$(field "$out" '1. Problem Statement' 1)" = "3" ] \
   && [ "$(summary "$out" REGISTER)" = "1" ] \
   && ! printf '%s' "$out" | $GREP -q $'\r'; then
    pass "CRLF input yields clean section names and counts"
else
    fail "CRLF input yields clean section names and counts" "$(printf '%s' "$out" | cat -A | head -4)"
fi

empty="$TMPDIR_ROOT/empty.md"; : > "$empty"
out=$(bash "$SCRIPT" "$empty" 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(field "$out" TOTAL 1)" = "0" ] \
    && pass "empty file reports zero, not an error" \
    || fail "empty file reports zero, not an error" "rc=$rc out=$out"

# An unclosed fence hides everything after it, so a count would be a lie. This must BLOCK,
# not warn: the register total is a gate, and a document with violations after an unclosed
# fence previously reported zero hits and exit 0.
unc=$(doc unclosed '## 5. Detailed Design\n\nalpha\n\n```bash\necho hi\n\nthe queue is deliberately unbounded and by design')
assert_blocks "unclosed fence BLOCKs rather than reporting zero" "BLOCKER: unclosed" "$unc"

# Setext headings are not supported as boundaries; the script must say so rather than
# silently attribute their prose to the previous section.
# A setext heading merges two sections into one budget, which would zero the ceiling gate
# on a document that is over it — the same lie as counting past an unclosed fence.
setx=$(doc setext 'Problem Statement\n-----\nalpha beta')
assert_blocks "a setext heading BLOCKs" "BLOCKER: 1 setext heading" "$setx"

# A --- after a blank line is a horizontal rule, which DESIGN-TEMPLATE uses throughout.
path=$(doc hrule 'alpha beta\n\n---\n\ngamma')
out=$(bash "$SCRIPT" "$path" 2>&1)
! printf '%s' "$out" | $GREP -q setext && [ "$(field "$out" TOTAL 1)" = "3" ] \
    && pass "a horizontal rule is not mistaken for a setext heading" \
    || fail "a horizontal rule is not mistaken for a setext heading" "$out"

# --- register detail block ----------------------------------------------------
path=$(doc detail '## 5. Detailed Design\n\nthe backing queue is deliberately unbounded so writers never block')
out=$(bash "$SCRIPT" "$path" 2>&1)
# Assert the whole row shape. Grepping for the token alone was satisfied by the snippet on
# the same line, so both the section and token columns could be falsified undetected.
if printf '%s\n' "$out" | $AWKBIN -F'\t' '
      /^  / { s=$1; sub(/^  /,"",s); if (s=="5. Detailed Design" && $2=="deliberately" && $3 ~ /unbounded so writers/) f=1 }
      END { exit !f }'; then
    pass "register detail row names section, token, and window in separate fields"
else
    fail "register detail row names section, token, and window in separate fields" "$out"
fi

path=$(doc noline 'alpha\nbeta\ngamma deliberately delta')
out=$(bash "$SCRIPT" "$path" 2>&1)
printf '%s\n' "$out" | $GREP -q '\.md:[0-9]' \
    && fail "register detail emits no file:line locator" "$out" \
    || pass "register detail emits no file:line locator"

# Window bounds: 5 words back, 7 forward, with ... markers only where truncation happened.
long='## 5. Detailed Design\nw1 w2 w3 w4 w5 w6 w7 deliberately w8 w9 w10 w11 w12 w13 w14 w15 w16'
path=$(doc window "$long")
out=$(bash "$SCRIPT" "$path" 2>&1)
win=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '/^  /{print $3; exit}')
[ "$win" = "...w3 w4 w5 w6 w7 deliberately w8 w9 w10 w11 w12 w13 w14..." ] \
    && pass "the window spans 5 words back and 7 forward with truncation markers" \
    || fail "the window spans 5 words back and 7 forward with truncation markers" "got='$win'"

path=$(doc window2 'deliberately w1 w2')
out=$(bash "$SCRIPT" "$path" 2>&1)
win=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '/^  /{print $3; exit}')
[ "$win" = "deliberately w1 w2" ] \
    && pass "an untruncated window carries no markers" \
    || fail "an untruncated window carries no markers" "got='$win'"

# Hits on one line are emitted in document order, not detector-list order.
path=$(doc hitorder 'of course this is deliberately fine')
out=$(bash "$SCRIPT" "$path" 2>&1)
got=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '/^  /{printf "%s ", $2}')
[ "$got" = "of course deliberately " ] \
    && pass "hits on one line are emitted in document order" \
    || fail "hits on one line are emitted in document order" "got='$got'"

# --- multiple files -----------------------------------------------------------
a=$(doc multi_a 'alpha beta'); b=$(doc multi_b 'gamma')
out=$(bash "$SCRIPT" "$a" "$b" 2>&1)
n=$(printf '%s\n' "$out" | $GREP -c '^== ')
# Per-file attribution, not just block cardinality: reading the wrong file per iteration
# still produced two blocks and left the suite green.
wa=$(printf '%s\n' "$out" | $AWKBIN -F'\t' -v f="$a" '$0 ~ ("^== " f " ==") {seen=1} seen && $1 ~ /^TOTAL/ {v=$2; sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v); print v; exit}')
wb=$(printf '%s\n' "$out" | $AWKBIN -F'\t' -v f="$b" '$0 ~ ("^== " f " ==") {seen=1} seen && $1 ~ /^TOTAL/ {v=$2; sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v); print v; exit}')
[ "$n" = "2" ] && [ "$wa" = "2" ] && [ "$wb" = "1" ] \
    && pass "each file gets its own block with its own numbers" \
    || fail "each file gets its own block with its own numbers" "blocks=$n a=$wa b=$wb :: $out"

# --- detector list is documented twice; the copies must agree ------------------
# Both extractions are bounded at BOTH ends, and each must match exactly once. An earlier
# version anchored on the list's last token, so an appended token was invisible; the version
# after that used head -1, so a duplicate correct line masked drift in the real one.
sc_n=$($GREP -c 'split("deliberately[^"]*"' "$SCRIPT")
ag_n=$($GREP -c -x 'deliberately|.*' "$AGENT_DOC")
cx_n=$($GREP -c -x 'deliberately|.*' "$CODEX_DOC")
script_list=$($GREP -o 'split("deliberately[^"]*"' "$SCRIPT" | /usr/bin/sed 's/^split("//; s/"$//')
agent_list=$($GREP -x 'deliberately|.*' "$AGENT_DOC")
codex_list=$($GREP -x 'deliberately|.*' "$CODEX_DOC")
if [ "$sc_n" != "1" ]; then
    fail "detector list appears exactly once in the script" "found $sc_n"
else
    pass "detector list appears exactly once in the script"
fi
if [ "$ag_n" != "1" ]; then
    fail "detector list appears exactly once in the agent doc" "found $ag_n"
else
    pass "detector list appears exactly once in the agent doc"
fi
if [ "$cx_n" != "1" ]; then
    fail "detector list appears exactly once in the Codex skill" "found $cx_n"
else
    pass "detector list appears exactly once in the Codex skill"
fi
# Three copies now: the script owns it, and both authoring skills publish it. Comparing
# only two let the third drift untested.
if [ -n "$script_list" ] && [ "$script_list" = "$agent_list" ] && [ "$script_list" = "$codex_list" ]; then
    pass "detector list matches across script, agent doc, and Codex skill"
else
    fail "detector list matches across script, agent doc, and Codex skill" \
         "script='$script_list' agent='$agent_list' codex='$codex_list'"
fi

# The three checks above name their files as constants, so they test the copies someone
# remembered to add — going from two copies to three required editing this suite. Discover
# every publication site instead, and require the named constants to be exactly that set:
# a fourth copy then joins the comparison by existing, rather than by being remembered.
_root="$(cd "$(dirname "$0")/.." && pwd)"
discovered=$(cd "$_root" && $GREP -rl -x 'deliberately|.*' --include='*.md' platforms/ 2>/dev/null | sort)
declared=$(printf '%s\n%s\n' "${AGENT_DOC#"$_root/"}" "${CODEX_DOC#"$_root/"}" | sort)
if [ "$discovered" = "$declared" ]; then
    pass "the detector list is published in exactly the two documents this suite names"
else
    fail "the detector list is published in exactly the two documents this suite names" \
         "$(diff <(printf '%s\n' "$declared") <(printf '%s\n' "$discovered") \
            | /usr/bin/sed 's/^</  only declared: /; s/^>/  only on disk: /')"
fi

out=$(bash "$SCRIPT" "$AGENT_DOC" 2>&1)
[ "$(summary "$out" REGISTER)" = "0" ] \
    && pass "the agent doc does not trip its own detector" \
    || fail "the agent doc does not trip its own detector" "$out"

# --- the real corpus must be measurable ---------------------------------------
# Every assertion above this line runs on a synthetic fixture, so the corpus this
# script exists to govern was never itself measured. Four config files once carried a
# ``` block nesting another ```, which inverts fence parity and makes the script exit
# BLOCKER — invisible in review, since an unbalanced fence reads as ordinary Markdown,
# and invisible here, because the only real-file assertion covers one file.
#
# Measurability is the property, not agreement: every awk emits the same BLOCKER on a
# broken fence, so an interpreter-agreement check passes straight through this defect.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
corpus_files=()
while IFS= read -r -d '' f; do corpus_files+=("$f"); done \
    < <(find "$REPO_ROOT/platforms" -name '*.md' -print0 | sort -z)

if [ "${#corpus_files[@]}" -eq 0 ]; then
    fail "the config corpus is measurable" "found no .md files under platforms/"
else
    out=$(bash "$SCRIPT" "${corpus_files[@]}" 2>&1); rc=$?
    blockers=$(printf '%s\n' "$out" | $GREP -c '^BLOCKER' || true)
    if [ "$rc" -eq 0 ] && [ "$blockers" -eq 0 ]; then
        pass "all ${#corpus_files[@]} config files under platforms/ are measurable"
    else
        fail "all ${#corpus_files[@]} config files under platforms/ are measurable" \
             "exit=$rc, $blockers BLOCKER line(s): $(printf '%s\n' "$out" | $GREP '^BLOCKER' | head -5)"
    fi
fi

# --- canon(): slot matching by whole words, not substrings -------------------
# A substring test put "Attestation" and "Contest Rules" in the Test slot, and gave
# "Trade-offs ... Testing" the Test ceiling instead of the Trade-offs target.
canon_slot() {   # canon_slot <heading> [<row-name>] -> the target cell, or "-"
    local path out
    path=$(doc "canon_$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')" "## $1\nalpha")
    out=$(bash "$SCRIPT" "$path" 2>&1)
    # The row name is the NORMALISED heading: tabs folded, whitespace runs collapsed.
    field "$out" "${2:-$1}" 4
}
assert_slot() {
    local got
    got=$(canon_slot "$2" "${4:-}")
    if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "heading '$2' target=$got want=$3"; fi
}
assert_slot "Attestation is not a Test section"        "Appendix C. Attestation Log"     "-"
assert_slot "Contest is not a Test section"            "Contest Rules"                   "-"
# "Latest Design Decisions" is a design section: it must not reach the Test slot, and
# the design fallback claims it for slot 5.
assert_slot "Latest Design Decisions is a design section" "Latest Design Decisions"  "4232"
assert_slot "Goalkeeper is not a Goals section"        "Goalkeeper Metrics"              "-"
assert_slot "Trade-offs outranks Testing"              "7. Trade-offs and Alternatives for Testing" "580"
assert_slot "Testing matches the Test slot"            "Testing Strategy"                "877"
assert_slot "a double space still canonises"           "5. Detailed  Design"             "4232" "5. Detailed Design"
assert_slot "a tab in a heading still canonises"       "5. Detailed	Design"           "4232" "5. Detailed Design"

# --- every published constant is asserted ------------------------------------
assert_slot "slot 1 target"  "1. Problem Statement"           "184"
assert_slot "slot 2 target"  "2. Goals and Non-Goals"         "283"
assert_slot "slot 3 target"  "3. Implementation Context"      "441"
assert_slot "slot 4 target"  "4. Architecture Overview"       "129"
assert_slot "slot 5 target"  "5. Detailed Design"             "4232"
assert_slot "slot 6 target"  "6. Test Requirements"           "877"
assert_slot "slot 7 target"  "7. Trade-offs and Alternatives" "580"
assert_slot "slot 8 target"  "8. Open Questions"              "45"
path=$(doc caps '## 5. Detailed Design\nalpha\n\n## 6. Test Requirements\nbeta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '5. Detailed Design' 5)" = "5463" ] && [ "$(field "$out" '6. Test Requirements' 5)" = "1754" ] \
    && pass "the two section ceilings are published" \
    || fail "the two section ceilings are published" "$out"

# --- register attribution and phrase boundaries ------------------------------
# A hit in a heading belongs to the section that heading OPENS, not the one it closes.
path=$(doc hdgattr '## 1. Problem Statement\nalpha\n## 5. Detailed Design deliberately\nbeta')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '1. Problem Statement' 3)" = "0" ] \
    && [ "$(field "$out" '5. Detailed Design deliberately' 3)" = "1" ] \
    && pass "a register hit in a heading belongs to the section it opens" \
    || fail "a register hit in a heading belongs to the section it opens" "$out"

assert_total "a phrase cannot span a full stop"     'Take note. That is the constraint.'   6 0
assert_total "a phrase cannot span a colon"         'One note: that path is hot.'          6 0
assert_total "a phrase cannot span a cell boundary" '| adds a note | that the caller reads |' 3 0
assert_total "the same phrase still counts intact"  'please note that the path is hot'     7 1

# --- fences: the cases the rewrite touched -----------------------------------
assert_total "a blockquoted fence closes itself" \
    'one\n> ```\n> alpha beta\n> ```\ntwo'                                                 2 0
assert_total "a blockquoted fence does not close a plain one" \
    'intro\n```\n> ```\n> deliberately unbounded by design\n> ```\n```\noutro'             2 0
assert_total "a four-space-indented fence marker is content" \
    'one\n```\ncat <<EOF\n    ```\nEOF\n```\ntwo'                                          2 0
# The run-length floor: without it a line opening with an inline code span or ~~strike~~
# would open a fence and swallow the rest of the document.
assert_total "a one-backtick line does not open a fence"  '`path` is the file\nalpha beta' 6 0
assert_total "a strikethrough line does not open a fence" '~~gone~~ now\nalpha beta'       4 0

# --- YAML frontmatter ---------------------------------------------------------
# The closing --- is indistinguishable from a setext underline, which made every agent
# and command file in this config BLOCK.
assert_total "YAML frontmatter is skipped, not read as setext" \
    '---\nname: thing\nmodel: opus\n---\n\nalpha beta gamma'                               3 0

# --- frontmatter and blockquoted fences: four fail-open cases, all exit 0 before ------
# Unclosed frontmatter swallowed the entire document and reported TOTAL 0 at rc=0 — the
# same class as an unclosed fence, but the whole file rather than a tail.
fmu=$(doc fm_unclosed '---\nname: thing\nmodel: opus\n\n## 5. Detailed Design\n\nNote that this is prose.')
assert_blocks "unclosed YAML frontmatter BLOCKs" "BLOCKER: unclosed YAML frontmatter" "$fmu"

# A leading --- with no YAML key after it is a horizontal rule. Reading it as a
# frontmatter opener discarded every line up to the next ---.
assert_total "a leading --- rule is not frontmatter" \
    '---\n# Design\n\n## 5. Detailed Design\n\nplease note that the path is hot\n\n---\n\nalpha' 8 1

# A fence opened inside a blockquote ends with the blockquote. Without this it stayed open
# over the rest of the document and every following paragraph was discarded, register and
# all, at exit 0.
assert_total "a blockquoted fence ends with the blockquote" \
    '> ```sh\n> make build\n\nplease note that this paragraph is prose\n\n```sh\nfenced\n```\n\ntail words here' 10 1

# A heading that matches no slot has no ceiling, so a large unslotted section is invisible
# to the length gate. It must at least be reported.
path=$(doc unslotted '## Feature-specific Section\n\nalpha beta gamma delta')
out=$(bash "$SCRIPT" "$path" 2>&1)
printf '%s' "$out" | $GREP -q 'UNSLOTTED: 1 section(s) holding 4 word(s)' \
    && pass "an unslotted section is reported" \
    || fail "an unslotted section is reported" "$out"

# --- inline code spans: exempt a mention, not an adjacent code word -------------
assert_total "one code-formatted word does not exempt a phrase" 'This is on by `design` here'  6 1
assert_total "a phrase inside a code span is exempt"            'see `in other words` here'    5 0
assert_total "a stray trailing backtick does not exempt"        'the flag is set deliberately`' 5 1
# A span often opens on a token carrying no alphanumeric at all. Tracking span state only
# for real words left the span closed for everything inside it.
assert_total "a span opening on a markup-only token still exempts" 'a hit in `## 5. Design deliberately` was recorded' 8 0

# --- the first H1 is a title, not a section ------------------------------------
path=$(doc h1title '# Design — Smoke Test Baseline\n\n## 5. Detailed Design\n\nalpha')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" 'Design — Smoke Test Baseline' 4)" = "-" ] \
    && pass "the document title claims no slot" \
    || fail "the document title claims no slot" "$out"

# A Design or Design Decisions heading is the same slot as Detailed Design; without this
# the corpus largest design section was unslotted and the ceiling could not see it.
assert_slot "Design Decisions is a design section" "4. Design Decisions" "4232"
assert_slot "Open Items is an Open Questions section" "8. Open Items" "45"

# --- output shape -------------------------------------------------------------
path=$(doc tabhdg '## 5. Detailed	Design\nalpha beta')
out=$(bash "$SCRIPT" "$path" 2>&1)
n=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '/^5\. Detailed/{print NF; exit}')
[ "$n" = "7" ] \
    && pass "a tab in a heading does not shift the columns" \
    || fail "a tab in a heading does not shift the columns" "fields=$n :: $out"

path=$(doc totalname '## TOTAL\nalpha\n## 5. Detailed Design\nbeta gamma delta')
out=$(bash "$SCRIPT" "$path" 2>&1)
n=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '{v=$1; sub(/[ \t]+$/,"",v); if (v=="TOTAL") c++} END{print c+0}')
[ "$n" = "1" ] && [ "$(field "$out" TOTAL 1)" = "4" ] && [ "$(field "$out" 'TOTAL (2)' 1)" = "1" ] \
    && pass "a section named TOTAL does not collide with the summary row" \
    || fail "a section named TOTAL does not collide with the summary row" "rows=$n :: $out"

# Every table row carries all seven fields, including the TOTAL row — a missing cell
# collapses the row for any caller reading columns.
path=$(doc fields '## 5. Detailed Design\nalpha beta')
out=$(bash "$SCRIPT" "$path" 2>&1)
bad=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '/^[^ =]/ && !/^REGISTER|^CEILING|^UNSLOTTED|^register hits|^COST|^MISSES|^FROM|^UNTAGGED/ {if (NF != 7) c++} END {print c+0}')
[ "$bad" = "0" ] \
    && pass "every table row carries seven tab-separated fields" \
    || fail "every table row carries seven tab-separated fields" "$bad malformed :: $out"

# --- symbols are not words ----------------------------------------------------
assert_total "check marks are not words"    'alpha \xe2\x9c\x93 beta'                       2 0
assert_total "warning signs are not words"  'alpha \xe2\x9a\xa0 beta'                       2 0
assert_total "math operators are not words" 'alpha \xe2\x89\xa5 beta'                       2 0
assert_total "multiplication sign is not a word" 'alpha \xc3\x97 beta'                      2 0
# The Latin-1 punctuation block holds three letters; stripping the block wholesale lost them.
assert_total "the micro sign is a word"          'alpha \xc2\xb5 beta'                      3 0
assert_total "ordinal indicators are words"      'alpha \xc2\xaa \xc2\xba beta'           4 0
assert_total "copyright and guillemet are not"   'alpha \xc2\xa9 \xc2\xab beta'           2 0
assert_total "emoji are not words"          'alpha \xf0\x9f\x98\x80 beta'                   2 0

# --- input guards added this round --------------------------------------------
unr="$TMPDIR_ROOT/unreadable.md"; printf 'alpha\n' > "$unr"; chmod 000 "$unr"
if [ -r "$unr" ]; then
    skip "an unreadable file BLOCKs with its own message (running as root?)"
else
    assert_blocks "an unreadable file BLOCKs with its own message" "BLOCKER: not readable" "$unr"
fi
chmod 644 "$unr"

# An awk that measures and THEN dies. The stub that emits nothing is caught by the
# no-table branch, so without this case the exit-status branch is individually deletable.
dieawk="$TMPDIR_ROOT/dieawk"
printf '#!/bin/sh\n%s "$@"\nexit 4\n' "$(command -v gawk || command -v awk)" > "$dieawk"
chmod +x "$dieawk"
out=$(DOC_METRICS_AWK="$dieawk" bash "$SCRIPT" "$path" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'no usable measurement' \
    && pass "an awk that measures then dies BLOCKs" \
    || fail "an awk that measures then dies BLOCKs" "rc=$rc out=$out"

# Multi-file where one file BLOCKs: the caller must not read a clean REGISTER line from a
# sibling and conclude the set is clean.
ok1=$(doc mf_ok1 'alpha beta'); bad=$(doc mf_bad 'one\n```\nunterminated'); ok2=$(doc mf_ok2 'gamma')
out=$(bash "$SCRIPT" "$ok1" "$bad" "$ok2" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | $GREP -q 'BLOCKER: unclosed' \
    && pass "one blocking file makes the whole run BLOCK" \
    || fail "one blocking file makes the whole run BLOCK" "rc=$rc out=$out"

# --- static guard: no interval quantifiers ------------------------------------
# Some mawk builds ignore {n,m}, so a heading rule written with one matches literal
# braces and nothing is a heading. This has recurred twice; the agreement block cannot
# catch it because every interpreter on this box honours intervals.
n=$($GREP -c '{[0-9][0-9]*,[0-9]*}' "$SCRIPT" || true)
[ "$n" = "0" ] \
    && pass "the script uses no interval quantifiers" \
    || fail "the script uses no interval quantifiers" "$n occurrence(s) — some mawk builds ignore them"

# --- mention rule: one-sided quotes are uses ----------------------------------
assert_total "an opening quote alone is a use"  'he said "deliberately and stopped'         5 1
assert_total "a closing quote alone is a use"   'it was deliberately" he said'              5 1

# --- register in deeper headings ----------------------------------------------
assert_total "a level-3 heading register hit counts" '## 5. Detailed Design\n### Deliberately unbounded\nalpha' 1 1

# --- awk agreement ------------------------------------------------------------
# The corpus must contain a multibyte `##` heading under 38 characters. Without one, every
# padded field is ASCII and the byte-vs-character padding divergence is invisible — the
# defect that made this block pass while nine real files disagreed.
#
# M6: the corpus also carries a §3 and a §7 section (added below) so this, the suite's only
# cross-interpreter guard, actually reaches the design-field scan — without them every one of
# the four new counters read zero on every interpreter and the detail block never printed, so
# a per-interpreter divergence in the 186 new lines had no assertion able to see it.
corpus="$TMPDIR_ROOT/corpus.md"
cat > "$corpus" <<'FIXTURE'
**Goal:** compaction

## 1. Problem — queue §4

The queue is deliberately unbounded — writers never block, which is what makes the
producer path allocation-free.

| lever | effect |
|---|---|
| dedup | deliberately excluded |

## 5. Detailed Design

```bash
echo "deliberately fenced"
```

> the ticket says this was intentionally deferred

Essentially the same argument appears twice; note that it should be noted here too.

### Sub-heading rolls up

Of course by design in other words that said crucially fundamentally importantly.

日本語 のテキスト and Привет мир.

## 3. Implementation Context

**Functional Requirements:**
- deliver the cost column — **From:** decision 2026-08-06
- flag missing evidence — **From:** ticket 464
- untagged bullet carries no tag at all

**Non-Functional Requirements:**
- no numeric threshold anywhere — **From:** hunch

**From:** analysis

**Context Files:**
- platforms/claude/scripts/doc-metrics.sh **From:** ticket 464

## 7. Trade-offs and Alternatives

### Option A
**Cost:** ~10 LOC
**Misses:** none

### Option B
**Cost:** ~5 LOC

### Option C
**Pros:** reuses existing code
**Cons:** slower
FIXTURE
/usr/bin/sed -i 's/\\u2014/—/; s/\\u00a7/§/' "$corpus"
printf '%s' "$(cat "$corpus")" | $GREP -q '^## 1. Problem — queue §4' \
    || { echo "  FAIL: corpus multibyte heading not written"; FAIL=$((FAIL+1)); }

reference=""; nawk=0; seen_real=""
for A in gawk mawk awk busybox-awk; do
    case "$A" in
        busybox-awk)
            command -v busybox >/dev/null 2>&1 || continue
            runner="$TMPDIR_ROOT/busybox-awk"
            printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$runner"
            chmod +x "$runner"; real=$(readlink -f "$(command -v busybox)") ;;
        *) command -v "$A" >/dev/null 2>&1 || continue
           runner="$A"; real=$(readlink -f "$(command -v "$A")") ;;
    esac
    # Dedupe by resolved target: `awk` is an alternatives symlink and resolved to gawk here,
    # so counting it as a fourth interpreter overstated the coverage.
    case " $seen_real " in *" $real "*) continue ;; esac
    seen_real="$seen_real $real"
    nawk=$((nawk + 1))
    got=$(DOC_METRICS_AWK="$runner" bash "$SCRIPT" "$corpus" 2>&1)
    if [ -z "$reference" ]; then
        # M10: the register check alone let the design-field scan (§3/§7 of the corpus fixture)
        # drop out of coverage silently — editing those blocks out would return COST/MISSES/
        # FROM/UNTAGGED to zero on every interpreter, with no "hits" block, and this guard
        # would not have noticed, which is the exact blind spot the round-1 finding was raised
        # against. Require all four counters non-zero and the design-field hits block present,
        # not only the register block.
        c_g=$(summary "$got" COST); m_g=$(summary "$got" MISSES)
        f_g=$(summary "$got" FROM); u_g=$(summary "$got" UNTAGGED)
        if printf '%s' "$got" | $GREP -q 'register hits' && [ "$(summary "$got" REGISTER)" -gt 5 ] \
           && printf '%s' "$got" | $GREP -q 'design-field hits' \
           && [ "${c_g:-0}" -gt 0 ] && [ "${m_g:-0}" -gt 0 ] \
           && [ "${f_g:-0}" -gt 0 ] && [ "${u_g:-0}" -gt 0 ]; then
            reference="$got"; pass "$A produced a non-empty baseline, register and all four design-field counters alike"
        else
            fail "$A produced a non-empty baseline, register and all four design-field counters alike" \
                 "COST=$c_g MISSES=$m_g FROM=$f_g UNTAGGED=$u_g :: $got"; break
        fi
    elif [ "$got" = "$reference" ]; then
        pass "$A agrees with the baseline byte for byte"
    else
        fail "$A agrees with the baseline byte for byte" \
             "$(diff <(printf '%s' "$reference") <(printf '%s' "$got") | head -8)"
    fi
done
[ "$nawk" -ge 2 ] \
    && pass "at least two distinct awk interpreters were compared ($nawk)" \
    || fail "at least two distinct awk interpreters were compared" "only $nawk found — agreement untested"

# The LC_ALL=C pin is required for EXECUTION, not merely for consistency: count_words uses
# byte-range regexes, which are invalid collation ranges in a UTF-8 locale, and gawk aborts
# on them. Asserting that directly is the honest form. An earlier version compared the two
# interpreters' output without the pin and called a difference "divergence" — but one side
# was gawk's abort message and the other a table, so the comparison was satisfied by the
# crash and would have passed on a corpus with no multibyte content at all.
utf8=$(locale -a 2>/dev/null | $GREP -m 1 -i 'utf-\?8$')
if [ -n "$utf8" ] && command -v gawk >/dev/null 2>&1; then
    nopin="$TMPDIR_ROOT/nopin.sh"
    /usr/bin/sed 's|^export LC_ALL=C$|: # pin removed for this test|' "$SCRIPT" > "$nopin"
    unpinned=$(LC_ALL="$utf8" DOC_METRICS_AWK=gawk bash "$nopin" "$corpus" 2>&1)
    pinned=$(LC_ALL="$utf8" DOC_METRICS_AWK=gawk bash "$SCRIPT" "$corpus" 2>&1)
    if [ "$(printf '%s\n' "$unpinned" | $GREP -c '^TOTAL')" = "0" ] \
       && [ "$(printf '%s\n' "$pinned"   | $GREP -c '^TOTAL')" = "1" ]; then
        pass "the LC_ALL=C pin is required for gawk to run at all under $utf8"
    else
        fail "the LC_ALL=C pin is required for gawk to run at all under $utf8" \
             "unpinned should produce no table and pinned exactly one; got $(printf '%s\n' "$unpinned" | $GREP -c '^TOTAL') and $(printf '%s\n' "$pinned" | $GREP -c '^TOTAL')"
    fi

    # And with the pin, a UTF-8 caller locale changes nothing for any interpreter.
    diverged=""
    for A in gawk mawk; do
        command -v "$A" >/dev/null 2>&1 || continue
        a=$(DOC_METRICS_AWK=$A bash "$SCRIPT" "$corpus" 2>&1)
        b=$(LC_ALL="$utf8" DOC_METRICS_AWK=$A bash "$SCRIPT" "$corpus" 2>&1)
        [ "$a" = "$b" ] || diverged="$diverged $A"
    done
    [ -z "$diverged" ] \
        && pass "with the pin, a UTF-8 caller locale changes nothing" \
        || fail "with the pin, a UTF-8 caller locale changes nothing" "diverged:$diverged"
else
    skip "the LC_ALL=C pin is required for gawk to run at all (needs gawk and a UTF-8 locale)"
    skip "with the pin, a UTF-8 caller locale changes nothing"
fi

# The share cell is locale-sensitive in mawk unless LC_ALL is pinned.
MAWK=$(command -v mawk 2>/dev/null || command -v awk)
if locale -a 2>/dev/null | $GREP -qi '^ru_RU.utf8$'; then
    got=$(LC_ALL=ru_RU.utf8 DOC_METRICS_AWK=${MAWK:-awk} bash "$SCRIPT" "$corpus" 2>&1)
    [ "$got" = "$reference" ] \
        && pass "a comma-decimal locale does not change the output" \
        || fail "a comma-decimal locale does not change the output" "$(diff <(printf '%s' "$reference") <(printf '%s' "$got") | head -4)"
else
    skip "a comma-decimal locale does not change the output (ru_RU.utf8 absent)"
fi

# --- design-field presence check (mechanism-proportionality) -----------------
# §7 Cost:/Misses: and §3 From: tags. U1-U27 per design.md §6; I1 and I6 are the two
# integration cases this suite owns (I2-I4 live in test_template_contracts.py, I5 in
# verify-config-consistency.sh).

# assert_fields <case> <body> <want-cost> <want-misses> <want-from> <want-untagged>
assert_fields() {
    local name="$1" body="$2" wc="$3" wm="$4" wf="$5" wu="$6" path out gc gm gf gu
    path=$(doc "$name" "$body")
    out=$(bash "$SCRIPT" "$path" 2>&1)
    gc=$(summary "$out" COST); gm=$(summary "$out" MISSES)
    gf=$(summary "$out" FROM); gu=$(summary "$out" UNTAGGED)
    if [ "$gc" = "$wc" ] && [ "$gm" = "$wm" ] && [ "$gf" = "$wf" ] && [ "$gu" = "$wu" ]; then
        pass "$name"
    else
        fail "$name" "want C=$wc M=$wm F=$wf U=$wu, got C=$gc M=$gm F=$gf U=$gu :: $out"
    fi
}

assert_fields "U1 two complete option blocks" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** none\n\n### Option B\n**Cost:** ~20 LOC\n**Misses:** FR-1\n' \
    0 0 0 0

assert_fields "U2 option block with Pros/Cons only" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Pros:** x\n**Cons:** y\n' \
    1 0 0 0

assert_fields "U3 option block with Cost and no Misses" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n' \
    0 1 0 0

assert_fields "U4 option block with Misses and no Cost" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Misses:** none\n' \
    1 0 0 0

assert_fields "U5 Misses label with no value" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:**\n' \
    0 1 0 0

assert_fields "U6 two blocks, second Cost-only" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10\n**Misses:** none\n\n### Option B\n**Cost:** ~20\n' \
    0 1 0 0

assert_fields "U7 H4 inside a complete option block" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10\n**Misses:** none\n#### Sub-heading\nmore text\n' \
    0 0 0 0

assert_fields "U8 H3 with no Cost outside slot 7" \
    '## 5. Detailed Design\n\n### Sub heading\nsome text\n' \
    0 0 0 0

assert_fields "U9 the only Cost line sits inside a fence" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n```\n**Cost:** ~10 LOC\n```\n**Misses:** none\n' \
    1 0 0 0

assert_fields "H1a a Misses: mention in Cons prose does not satisfy a missing Misses: field" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Cons:** this **Misses:** nothing critical\n' \
    0 1 0 0

assert_fields "H1b a Cost: mention in Pros prose does not satisfy a missing Cost: field" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Pros:** reuses the existing **Cost:** tracking mechanism\n**Cons:** slower\n' \
    1 0 0 0

# M1: the H1 line-start anchoring (above) fixed the mention-vs-use hole but regressed every
# form that puts something before the label on its own line — a list marker, a blockquote
# marker, or a table pipe. All four forms counted before that anchoring change. field_scan
# strips those prefixes for slot 7 only (strip_field_prefix()) before testing the anchor —
# slot 3 keeps the raw line, since a stripped list marker there would put a bold label at
# position 0, where the group-opener test would misread it (§5.3), a hazard slot 7 does not
# have.
assert_fields "M1a Cost and Misses written as list items are still recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n- **Cost:** ~10 LOC\n- **Misses:** none\n' \
    0 0 0 0

assert_fields "M1b a list-item Cost paired with a plain-line Misses are both recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n- **Cost:** ~10 LOC\n**Misses:** none\n' \
    0 0 0 0

assert_fields "M1c Cost and Misses inside a blockquote are still recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n> **Cost:** ~10 LOC\n> **Misses:** none\n' \
    0 0 0 0

assert_fields "M1d Cost and Misses written as table cells are still recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** ~10 LOC | prod |\n|---|---|\n| **Misses:** none | - |\n' \
    0 0 0 0

# H2 (round 3): the table analogue of U5 — a Misses: label present as a table cell, but the
# value cell empty. strip_field_prefix() only removes the OPENING pipe of the cell, so the
# CLOSING "| |" from the rest of the row rode along into the extracted value: non-empty by
# accident, so the blocker never fired. M1d above only exercises a POPULATED table cell and
# passes either way, so it cannot see this.
assert_fields "H2 (round 3) a Misses table cell with an empty value blocks, not read as clean" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | ~10 LOC |\n| **Misses:** | |\n' \
    0 1 0 0

# D1: H2's positive counterpart — the same two-column shape (label and value in SEPARATE
# cells) but with the value cell actually populated. Before D1, sub(/\|.*\$/, "", val) cut at
# the FIRST pipe regardless of which side of a cell boundary it opened, so "| **Misses:** |
# none |" and "| **Misses:** | |" were indistinguishable: both truncated to "". H2 alone only
# proves the empty case reads as absent; it cannot tell a truncation bug from a working
# blocker, since both report MISSES: 1 here. This is the discriminating case.
assert_fields "D1 a Misses table cell with the value in a separate, populated cell reads clean" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | ~10 LOC |\n| **Misses:** | none |\n' \
    0 0 0 0

# D2: a plain (non-table) Misses: line whose value legitimately contains a pipe. The D1 fix
# reads a pipe as a cell boundary only when the raw line is actually a table row (raw ~
# /^([ \t]*>)*[ \t]*\|/) — applying that same cut unconditionally, as an earlier version of
# the D1 fix did, truncated this plain line's value to "" too, indistinguishable from D1's
# genuinely-empty table cell. This fixture has Cost present so only MISSES is at risk.
assert_fields "D2 a plain-line Misses: value containing a pipe is not cut at it" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** | FR-1\n' \
    0 0 0 0

# D2b: the discriminating companion to D2 above. "| FR-1" happens to survive EITHER way — even
# with the is_table gate forced permanently on, stripping a leading boundary from "| FR-1" and
# cutting at the next one (there is none) still leaves "FR-1", non-empty either way, so that
# fixture alone cannot tell "the gate correctly stayed off" apart from "the gate fired and
# happened not to matter here". A bare trailing pipe with nothing after it closes that gap: read
# as a table cell it strips to "", read as plain content (correct, not a table row) it is "|",
# non-empty. Only the untreated reading is clean.
assert_fields "D2b a plain-line Misses: value that is only a pipe is not read as an empty table cell" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** |\n' \
    0 0 0 0

# M5: the leading-whitespace allowance itself (plain indentation, no list marker) had no
# assertion — only the mention-rejection half of the H1 anchor (H1a/H1b above) was covered.
assert_fields "M5 Cost and Misses indented with plain whitespace are recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n  **Cost:** ~10 LOC\n  **Misses:** none\n' \
    0 0 0 0

# D6: seventh round of the same class of defect — the scanner fixed for one input shape while
# the adjacent shape stayed broken (bold mentions, indentation, list markers, trailing-space
# labels, two-column cells, leading-space labels, now cell POSITION). strip_field_prefix strips
# exactly one leading pipe, so the Cost:/Misses: anchors could only ever match a label sitting
# in the FIRST cell of a table row — a Cost: and Misses: label sharing one row, or a label-row/
# value-row layout, left whichever field was NOT in cell 1 invisible. Fixed structurally: a
# table row is now split on its own pipes and every cell tested independently, closing the
# position dimension rather than moving the boundary one cell to the right.

# D6a: the headline reproduction — Cost and Misses share one row, template field order (Cost
# before Misses), both with inline values.
assert_fields "D6a Cost and Misses sharing one table row, both with inline values, are both recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** ~1 LOC | **Misses:** none |\n' \
    0 0 0 0

# D6b: the label-row/value-row form — Cost and Misses BOTH bare in one row, their values in
# the SAME COLUMN of the very next table row. No single row carries a label next to its own
# value here, so per-cell scanning alone cannot resolve it; miss_pending_col remembers the
# column a bare Misses: label was seen in and resolves it against the immediately following
# table row.
assert_fields "D6b the label-row/value-row table form is recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n| ~1 LOC | none |\n' \
    0 0 0 0

# D6c: reversed cell order — Misses before Cost, the opposite of the template's own field
# order, still fully recognised.
assert_fields "D6c Misses before Cost in one row, reversed field order, is still recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Misses:** none | **Cost:** ~1 LOC |\n' \
    0 0 0 0

# D6d: a three-cell row with an unrelated leading cell (an "Option" name column) pushes both
# labels to cells 2 and 3 — neither is cell 1, closing the position dimension for good rather
# than just moving it from cell 1 to cell 2.
assert_fields "D6d a three-cell row with both labels past cell 1 is still recognised" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| Option | **Cost:** ~1 LOC | **Misses:** none |\n' \
    0 0 0 0

# D6e: the empty-value blocker (H2, round 3) must still fire wherever the label sits, not only
# in cell 1 — a Misses: label past cell 1 with nothing after it is still an empty value.
assert_fields "D6e an empty Misses value in a non-first cell still blocks" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** ~1 LOC | **Misses:** |\n' \
    0 1 0 0

# D6f: the same-row adjacent-cell lookahead (inherited from D1) must not slurp a NEIGHBOURING
# label's own cell as if it were the value — a bare Misses: cell immediately followed by a
# bare Cost: cell is two label-only cells, not a Misses/value pair, and must still block.
assert_fields "D6f a bare Misses label immediately followed by a bare Cost label still blocks" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Misses:** | **Cost:** ~5 LOC |\n' \
    0 1 0 0

# D6g: the cross-row counterpart to D6f — the column remembered from a bare Misses: label
# must not be satisfied by a LATER row whose cell at that same column is itself another bare
# Misses: label (not a real value). Without the same Cost:/Misses: exclusion the cross-row
# path applies, a second unresolved label row would read as the first row's value.
assert_fields "D6g a pending column resolved against another bare label, not a real value, still blocks" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n| ~1 LOC | **Misses:** |\n' \
    0 1 0 0

# D6h: the cross-row lookahead is bounded to exactly the ONE row immediately following a bare
# label — consumed whether it resolves or not. A row that intervenes between the label row and
# a row that WOULD have supplied the value must break the chain: the value one row further out
# is not used, and the field still blocks. This is a deliberate, declared bound (D6's own
# reproduction is label-row-immediately-followed-by-value-row), not an oversight — unbounded
# lookahead risks a later, unrelated row being mistaken for the value.
assert_fields "D6h an intervening row breaks the one-row cross-row lookahead" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n| a | |\n| ~1 LOC | none |\n' \
    0 1 0 0

# D6i: miss_pending_col must not leak from one option block into the next. Block A arms it
# (bare Misses:, never resolved within the block) and closes still blocked; block B opens
# fresh with its own Cost: and an unrelated second cell that would be wrongly read as block
# B's OWN Misses value if the pending column leaked forward — block B has no Misses: label at
# all, so it must warn on its own account, not read as accidentally satisfied.
fxD6i=$(doc D6i '## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n\n### Option B\n| **Cost:** ~2 LOC | foo |\n')
outD6i=$(bash "$SCRIPT" "$fxD6i" 2>&1)
[ "$(summary "$outD6i" COST)" = "0" ] && [ "$(summary "$outD6i" MISSES)" = "2" ] \
    && pass "D6i miss_pending_col does not leak from one option block into the next" \
    || fail "D6i miss_pending_col does not leak from one option block into the next" \
         "cost=$(summary "$outD6i" COST) misses=$(summary "$outD6i" MISSES) :: $outD6i"

assert_fields "U10 section 7 omitted from the document entirely" \
    '## 5. Detailed Design\n\nno trade-offs here\n' \
    0 0 0 0

assert_fields "U11 section 7 present, options as bold lines and H4s" \
    '## 7. Trade-offs and Alternatives\n\n**Option A**\n**Cost:** ~10\n**Misses:** none\n\n#### Option B\n**Cost:** ~10\n**Misses:** none\n\n## 8. Open Questions\n\n*(None)*\n' \
    1 0 0 0

# H4: close_opt_block() and close_slot7_section() must fire correctly from the H1/H2
# section-change branch, not just from END — every real design.md has §7 followed by §8, so
# a call site exercised only at END is a silent hole (every prior §7 fixture ended the
# document there). U11 above now closes via the section-change branch, catching a dropped
# close_slot7_section() call there (COST would drop 1→0). This fixture additionally checks
# that the closed block's detail line still attributes the SECTION it belonged to (7, not the
# section that follows) — a bare counter check cannot see a close that fires at the right
# count but with the wrong `sec` already overwritten.
fxH4=$(doc H4boundary '## 7. Trade-offs and Alternatives\n\n### Option A\n**Misses:** none\n\n## 8. Open Questions\n\n*(None)*\n')
outH4=$(bash "$SCRIPT" "$fxH4" 2>&1)
detail_sec=$(printf '%s\n' "$outH4" | $AWKBIN -F'\t' '/^  /{s=$1; sub(/^  /,"",s); print s; exit}')
[ "$(summary "$outH4" COST)" = "1" ] && [ "$(summary "$outH4" MISSES)" = "0" ] \
    && [ "$detail_sec" = "7. Trade-offs and Alternatives" ] \
    && pass "H4 a slot-7 close at a section boundary fires once and attributes its detail line to the closed section, not the new one" \
    || fail "H4 a slot-7 close at a section boundary fires once and attributes its detail line to the closed section, not the new one" \
         "detail_sec='$detail_sec' :: $outH4"

# H2: close_slot7_section() at END was left unguarded by the fix that gave H4boundary (and
# U11, once this round moved its terminator to `## 8. Open Questions`) a section-change
# fixture — every §7-at-EOF case migrated away, leaving the END call site with no test that
# fails when it alone is deleted. commands/design.md permits omitting §8, so §7-at-EOF is a
# real production shape, not just a suite gap. This fixture ends the document IN §7, with no
# exact-H3 option block ever opened, so only the END call site can close it.
fxH2=$(doc H2eof '## 7. Trade-offs and Alternatives\n\n**Option A**\n**Cost:** ~10\n**Misses:** none\n')
outH2=$(bash "$SCRIPT" "$fxH2" 2>&1)
[ "$(summary "$outH2" COST)" = "1" ] && [ "$(summary "$outH2" MISSES)" = "0" ] \
    && pass "H2 a slot-7 section ending the document with no option block opened is still closed, at END" \
    || fail "H2 a slot-7 section ending the document with no option block opened is still closed, at END" "$outH2"

# H3 (round 3): close_slot7_section()'s internal `slot7_block_ever = 0` reset, not merely the
# call site itself. Section 1 opens a ### Option block carrying both fields and is clean —
# slot7_block_ever becomes 1. Section 2 is a second slot-7-canon heading whose "option" is a
# bold line, not a ### block, so slot7_block_ever must have been reset to 0 for section 2's own
# close to correctly find "no block opened". If the reset leaks, section 2 inherits section 1's
# true value and its own close_slot7_section() call sees a block that was never opened here at
# all: COST reads 0 instead of 1 and the detail line is lost.
fxH3s7=$(doc H3slot7reset '## 7. Trade-offs Analysis\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** none\n\n## Alternative Approaches Considered\n\n**Option B**\n**Cost:** ~5 LOC\n**Misses:** none\n\n## 8. Open Questions\n\n*(None)*\n')
outH3s7=$(bash "$SCRIPT" "$fxH3s7" 2>&1)
detailH3s7=$(printf '%s\n' "$outH3s7" | $AWKBIN -F'\t' '/^  /{s=$1; sub(/^  /,"",s); print s; exit}')
[ "$(summary "$outH3s7" COST)" = "1" ] && [ "$(summary "$outH3s7" MISSES)" = "0" ] \
    && [ "$detailH3s7" = "Alternative Approaches Considered" ] \
    && pass "H3 (round 3) close_slot7_section()'s slot7_block_ever reset does not leak across two slot-7 sections" \
    || fail "H3 (round 3) close_slot7_section()'s slot7_block_ever reset does not leak across two slot-7 sections" \
         "cost=$(summary "$outH3s7" COST) misses=$(summary "$outH3s7" MISSES) detail_sec='$detailH3s7' :: $outH3s7"

assert_fields "U12 one bullet per accepted From value" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item one \xe2\x80\x94 **From:** ticket 464\n- item two \xe2\x80\x94 **From:** incident 2026-08-06\n- item three \xe2\x80\x94 **From:** decision 2026-08-06\n- item four \xe2\x80\x94 **From:** spec RFC 7230\n- item five \xe2\x80\x94 **From:** analysis\n' \
    0 0 0 0

assert_fields "U13 unrecognised first token" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** hunch\n' \
    0 0 1 0

assert_fields "U14 incident with a non-ISO date" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** incident yesterday\n' \
    0 0 1 0

assert_fields "U15 spec and ticket each with no name" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item one \xe2\x80\x94 **From:** spec\n- item two \xe2\x80\x94 **From:** ticket\n' \
    0 0 2 0

assert_fields "U16 decision date followed by free prose" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** decision 2026-08-06 \xe2\x80\x94 the user chose this\n' \
    0 0 0 0

assert_fields "U17 bold label twice on one bullet, first invalid" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** hunch **From:** analysis\n' \
    0 0 1 0

# M1: U17 pairs one invalid label with one valid, so a first-match, last-match, or
# any-single-match rule all report the same FROM: 1 as the correct per-occurrence scan. Two
# invalid labels on one bullet distinguishes them — only validating every occurrence
# independently reaches FROM: 2.
assert_fields "M1 two invalid From labels on one bullet are both counted" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** hunch **From:** nonsense\n' \
    0 0 2 0

# M7: the §3 analogue of U5's empty Misses: case. Inverting from_valid()'s n < 1 guard would
# accept a bullet ending right at the label with nothing after it.
assert_fields "M7 a From: label with no value after it is invalid, not merely absent" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:**\n' \
    0 0 1 0

assert_fields "U18 From tag and untagged bullets outside slot 3" \
    '## 5. Detailed Design\n\n**From:** hunch\n\n**Functional Requirements:**\n- untagged one\n- untagged two\n' \
    0 0 0 0

assert_fields "U19 From tag inside a table row in slot 3" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n\n| col | **From:** hunch |\n|---|---|\n' \
    0 0 1 0

assert_fields "U20 untagged Constraint bullet plus Context Files and Verification bullets" \
    '## 3. Implementation Context\n\n**Constraints:**\n- untagged constraint\n\n**Context Files:**\n- path/to/file\n\n**Verification:**\n- some verification bullet\n' \
    0 0 0 1

assert_fields "U21 line-start From plus From on a Context Files bullet" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n**From:** analysis\n\n**Context Files:**\n- path/to/file **From:** ticket 464\n' \
    0 0 2 0

assert_fields "U22 inline bold span mid-bullet is not a group opener" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1: declares `**Cost:**` and `**Misses:**` fields \xe2\x80\x94 **From:** decision 2026-08-06\n- FR-2: untagged requirement text\n' \
    0 0 0 1

# M3: a bold label at line start inside an open requirement group closes it — correctly,
# since _collect_bullets() in markdown_parser.py really does stop there too — but the closed
# group's From: tag hits used to name the wrong line: the first bullet found afterward, not
# the label that closed the group, which pointed the author at stripping a correct tag
# instead of fixing the label. req_close_loc remembers the closing label's own opening words
# the moment a "req" group closes (field_scan), and every "outside the group" hit below it is
# attributed there instead.
pathM3=$(doc M3 '## 3. Implementation Context\n\n**Functional Requirements:**\n- item one \xe2\x80\x94 **From:** ticket 464\n\n**Notes:**\n- item two \xe2\x80\x94 **From:** ticket 465\n')
outM3=$(bash "$SCRIPT" "$pathM3" 2>&1)
detailM3=$(printf '%s\n' "$outM3" | $AWKBIN -F'\t' '/^  /{print $2 "\t" $3; exit}')
[ "$(summary "$outM3" FROM)" = "1" ] \
    && [ "$detailM3" = '**Notes:**	requirement group closed by this label; a From: tag below it is outside the group' ] \
    && pass "M3 a tag orphaned by a closing label is attributed to the label, not to the correctly-tagged bullet" \
    || fail "M3 a tag orphaned by a closing label is attributed to the label, not to the correctly-tagged bullet" \
         "detail='$detailM3' :: $outM3"

# H6: markdown_parser.py's _collect_bullets() strips leading whitespace before testing
# FIELD_PATTERN, so an indented bold label still breaks the parser even though an
# unindented-only "line start" test in the scanner cannot see it (the exact gap C3's
# line-start blocker exists to close, reopened through indentation).
#
# H6a: M4 extends the original fixture (which carried no bullet after the indented label, so
# it could not see the group silently closing) with two untagged bullets below it — reverting
# the whitespace allowance would let the generic bold-label branch (which still allows leading
# whitespace) claim the line instead, closing the group and dropping UNTAGGED from 2 to 0. M6
# additionally asserts the FROM hit's own reason string: both the fixed anchor and the
# reverted one reach FROM: 1, by two different paths that a bare count cannot tell apart.
pathH6a=$(doc H6a '## 3. Implementation Context\n\n**Functional Requirements:**\n  **From:** analysis\n- untagged one\n- untagged two\n')
outH6a=$(bash "$SCRIPT" "$pathH6a" 2>&1)
reasonH6a=$(printf '%s\n' "$outH6a" | $AWKBIN -F'\t' '/^  /{if ($3 ~ /must be inline/) {print $3; exit}}')
[ "$(summary "$outH6a" FROM)" = "1" ] && [ "$(summary "$outH6a" UNTAGGED)" = "2" ] \
    && [ -n "$reasonH6a" ] \
    && pass "H6a an indented From label opening its own line is caught as misplaced (C3), by its proper reason, and leaves the group open for the bullets below it" \
    || fail "H6a an indented From label opening its own line is caught as misplaced (C3), by its proper reason, and leaves the group open for the bullets below it" \
         "FROM=$(summary "$outH6a" FROM) UNTAGGED=$(summary "$outH6a" UNTAGGED) reason='$reasonH6a' :: $outH6a"

assert_fields "H6b an indented Context Files heading still closes the requirement group for misplacement checks" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** decision 2026-08-06\n\n  **Context Files:**\n- path/to/file **From:** ticket 464\n' \
    0 0 1 0

# H6c: UNTAGGED: 1 alone does not distinguish "the indented opener is recognised, and the
# per-bullet scan below it catches the untagged bullet" from "the opener goes unrecognised,
# and M2's close_slot3_section() fallback fires its own once-per-section warning instead" —
# both produce the same count. Assert the detail line's own locator and reason to tell them
# apart: the per-bullet path names the bullet's opening words as "requirement bullet with no
# From: tag"; the M2 fallback would instead name the section itself as "no requirement group
# opened in this section".
pathH6c=$(doc H6c '## 3. Implementation Context\n\n  **Functional Requirements:**\n- untagged bullet here\n')
outH6c=$(bash "$SCRIPT" "$pathH6c" 2>&1)
detailH6c=$(printf '%s\n' "$outH6c" | $AWKBIN -F'\t' '/^  /{print $2 "\t" $3; exit}')
[ "$(summary "$outH6c" UNTAGGED)" = "1" ] \
    && [ "$detailH6c" = "untagged bullet here	requirement bullet with no From: tag" ] \
    && pass "H6c an indented Functional Requirements group opener is still recognised, not just papered over by the section-level fallback" \
    || fail "H6c an indented Functional Requirements group opener is still recognised, not just papered over by the section-level fallback" \
         "detail='$detailH6c' :: $outH6c"

fx23=$(doc U23 '## 3. Implementation Context\n\n**Functional Requirements:**\n- item one \xe2\x80\x94 **From:** ticket 464\n- item two untagged\n\n**From:** hunch\n\n## 7. Trade-offs and Alternatives\n\n### Option A\n**Pros:** x\n**Cons:** y\n\n### Option B\n**Cost:** ~10 LOC\n')
out23=$(bash "$SCRIPT" "$fx23" 2>&1); rc23=$?
[ "$rc23" -eq 0 ] \
    && [ "$(summary "$out23" COST)" = "1" ] && [ "$(summary "$out23" MISSES)" = "1" ] \
    && [ "$(summary "$out23" FROM)" = "1" ] && [ "$(summary "$out23" UNTAGGED)" = "1" ] \
    && pass "U23 a fixture with all four counters non-zero still exits 0" \
    || fail "U23 a fixture with all four counters non-zero still exits 0" "rc=$rc23 :: $out23"

# U24: one indented detail line per hit, each carrying section \t locator \t reason (three
# fields, not two — dropping the section field must be caught, not just its absence-of-digits
# neighbour), and no locator that is digit-only (the code-reference rule forbids a bare
# line-number locator). M4: the shape alone is not the payload — assert the content too, or
# emitting the block with an empty section/locator/reason, or the same reason string for
# every hit, still passes. The detail block is the entire operator-facing output of the
# feature, so its four hits (one per counter, from fx23 above) must carry four DISTINCT
# reasons, not a single constant string reused everywhere.
n_detail=$(printf '%s\n' "$out23" | $AWKBIN -F'\t' '/^  /{c++} END{print c+0}')
bad_fields=$(printf '%s\n' "$out23" | $AWKBIN -F'\t' '/^  /{if (NF != 3) c++} END{print c+0}')
digit_only=$(printf '%s\n' "$out23" | $AWKBIN -F'\t' '/^  /{if ($2 ~ /^[0-9]+$/) c++} END{print c+0}')
empty_fields=$(printf '%s\n' "$out23" | $AWKBIN -F'\t' '/^  /{s=$1; sub(/^  /,"",s); if (s=="" || $2=="" || $3=="") c++} END{print c+0}')
distinct_reasons=$(printf '%s\n' "$out23" | $AWKBIN -F'\t' '/^  /{print $3}' | sort -u | wc -l | tr -d ' ')
[ "$n_detail" -eq 4 ] && [ "$bad_fields" -eq 0 ] && [ "$digit_only" -eq 0 ] \
    && [ "$empty_fields" -eq 0 ] && [ "$distinct_reasons" -eq 4 ] \
    && pass "U24 the detail block carries one indented section/locator/reason line per hit, no digit-only locator, no empty field, and four distinct reasons" \
    || fail "U24 the detail block carries one indented section/locator/reason line per hit, no digit-only locator, no empty field, and four distinct reasons" \
         "detail_lines=$n_detail bad_fields=$bad_fields digit_only_locators=$digit_only empty_fields=$empty_fields distinct_reasons=$distinct_reasons :: $out23"

# U25: the field scan must not consume its line — NFR-2 and every pinned target/ceiling stay
# valid only while the new scans leave the word count alone. Counts below are hand-computed,
# independent of the script, so a stray `next` in either field branch drops them.
path=$(doc U25 '## 3. Implementation Context\n\n**Functional Requirements:**\n- item one \xe2\x80\x94 **From:** ticket 464\n\n## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC production\n**Misses:** none\n')
out=$(bash "$SCRIPT" "$path" 2>&1)
[ "$(field "$out" '3. Implementation Context' 1)" = "7" ] \
    && [ "$(field "$out" '7. Trade-offs and Alternatives' 1)" = "6" ] \
    && pass "U25 the field scan does not consume its line — word counts are unaffected" \
    || fail "U25 the field scan does not consume its line — word counts are unaffected" "$out"

assert_fields "U26 a clean document prints all four counters as zero" \
    '## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10\n**Misses:** none\n' \
    0 0 0 0

assert_fields "U27 untagged bullets under both Functional and Non-Functional Requirements" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- untagged FR\n\n**Non-Functional Requirements:**\n- untagged NFR one\n- untagged NFR two\n' \
    0 0 0 3

# U28: the slot-3 counterpart to U11 (a slot-7 section closing with no ### block opened).
# Three malformed group-opener shapes never set req_group == "req", so the untagged bullets
# beneath each are individually invisible to the per-bullet scan; without a section-level
# closer the whole section reads UNTAGGED: 0, indistinguishable from fully tagged. M8 split
# what was one aggregate fixture into one case per shape, since a combined count could not
# say which shape a mutation had actually broken.

# U28a: an H4 heading never reaches field_scan at all — the H3+ heading branch consumes it
# and `next`s before field_scan ever sees the line — so this shape can ONLY be caught by
# close_slot3_section()'s section-level fallback.
assert_fields "U28a a heading-level Functional Requirements opener warns once, via the section closer" \
    '## 3. Implementation Context\n\n#### Functional Requirements\n- untagged one\n' \
    0 0 0 1

# U28b: a bulleted bold label fails every bold-label regex in field_scan, since none of them
# allow a list marker before the line-start `**` — also only caught by the section closer.
assert_fields "U28b a bulleted Functional Requirements opener warns once, via the section closer" \
    '## 3. Implementation Context\n\n- **Functional Requirements:**\n- untagged two\n' \
    0 0 0 1

# U28c / H1 (round 3, was M2): a space before the colon. markdown_parser.py strips the label
# before comparing it to the field name, so this line IS collected as a real Functional
# Requirements group in production. Reported wrong two ways before this fix: field_scan set
# req_group to "other" (not "req"), which made a VALID inline From: tag on a bullet beneath it
# read as misplaced (a false FROM: blocker on a correctly tagged requirement); and it left
# slot3_group_ever false, so close_slot3_section() ALSO fired its own "no group opened"
# fallback for the very same malformed opener — one real defect reported twice. The fix
# represents the near-miss explicitly: req_group becomes "req" (so From: validation treats a
# bullet beneath it as inside a group, matching production) and slot3_group_ever is set (so
# the section sentinel does not also fire), while req_scan_bullets stays 0 (so an untagged
# bullet beneath it is not ALSO individually flagged — the opener's own hit, reported
# unconditionally the instant it is seen, already tells the author where to look). Asserting
# the reason text, and the ABSENCE of the section-closer's reason, distinguishes this single,
# correctly-attributed warning from the old double count.
pathU28c=$(doc U28c '## 3. Implementation Context\n\n**Functional Requirements :**\n- untagged three\n')
outU28c=$(bash "$SCRIPT" "$pathU28c" 2>&1)
reasonsU28c=$(printf '%s\n' "$outU28c" | $AWKBIN -F'\t' '/^  /{print $3}')
# D5 revised the reason text from "a space before the colon" to "whitespace around the label
# inside **...**" when the near-miss branch widened to also admit a leading-space opener (see
# D5 below) — this trailing-space form is one instance of that wider set, so the wording it
# pins moved with it.
[ "$(summary "$outU28c" UNTAGGED)" = "1" ] && [ "$(summary "$outU28c" FROM)" = "0" ] \
    && printf '%s\n' "$reasonsU28c" | $GREP -q 'whitespace around the label' \
    && ! printf '%s\n' "$reasonsU28c" | $GREP -q 'no requirement group opened in this section' \
    && pass "U28c a spaced-colon Functional Requirements opener warns exactly once, not double-counted by the section closer" \
    || fail "U28c a spaced-colon Functional Requirements opener warns exactly once, not double-counted by the section closer" \
         "untagged=$(summary "$outU28c" UNTAGGED) from=$(summary "$outU28c" FROM) reasons='$reasonsU28c' :: $outU28c"

# H1 (round 3): the companion case — a spaced-colon opener whose one bullet carries a VALID
# inline From: tag. Before this fix this reported FROM: 1 (the tag misread as outside the
# group, since req_group was "other") on top of UNTAGGED: 2 (the opener's own hit plus the
# section-closer's duplicate) — a correctly tagged requirement raising a blocking counter.
assert_fields "H1 (round 3) a tagged spaced-colon group yields exactly one warning and FROM: 0" \
    '## 3. Implementation Context\n\n**Functional Requirements :**\n- FR-1: something \xe2\x80\x94 **From:** analysis\n' \
    0 0 0 1

# D5: the near-miss branch only admitted whitespace AFTER the label (before the colon) —
# "**Functional Requirements :**" — and missed whitespace BEFORE it — "** Functional
# Requirements:**". FIELD_PATTERN in markdown_parser.py captures everything between ** and :**
# as `name` and compares `name.strip() ==` the field name, so `.strip()` admits padding on
# EITHER end or both; a leading-space opener really is collected as a genuine requirement
# group in production, same as the trailing-space form. Before this fix it fell through past
# both the valid AND near-miss branches to the generic "other bold label" branch instead — its
# `[^*]+` class does not care where the spaces sit — which is worse than not matching: it set
# req_group to "other" as though this line CLOSED an earlier still-open group rather than
# opening its own, producing a false "requirement group closed by this label" on a correctly
# tagged bullet beneath it (reproduced live: confirmed FROM: 0/UNTAGGED: 0 — fully clean —
# before this fix, on a document whose requirement reaches codex-flow untagged).

# D5a: leading-space opener alone, untagged bullet beneath it — must warn once (the opener),
# not stay silent (the pre-fix behaviour) and not ALSO flag the bullet individually (req_scan_
# bullets stays 0 for every near-miss shape, same as the trailing-space form).
assert_fields "D5a a leading-space opener alone with an untagged bullet warns once" \
    '## 3. Implementation Context\n\n** Functional Requirements:**\n- untagged one\n' \
    0 0 0 1

# D5b: the M2 shape (a malformed opener after an already-valid group must still be reported,
# not suppressed by it) repeated for the leading-space form specifically — M2 only exercised
# the trailing-space spelling, and D3a only exercised the heading-level shape, so neither
# covers this one.
assert_fields "D5b a leading-space opener after a valid group still warns once" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1 \xe2\x80\x94 **From:** analysis\n\n** Non-Functional Requirements:**\n- untagged nfr\n' \
    0 0 0 1

# D5c: the exact reproduction from the live report — a leading-space opener AFTER a valid
# group, this time with a CORRECTLY tagged bullet beneath it. Before this fix this is the
# fixture that actually produced FROM: 1 with reason "requirement group closed by this label"
# (the generic-label branch closing the still-open FR group and misattributing the NFR
# bullet's own, perfectly valid, tag as orphaned by it). Asserting the reason text's absence,
# not just the counters, is the point: a subtly wrong fix could still land on FROM: 0 by
# accident while leaving the wrong attribution mechanism in place for some other input.
pathD5c=$(doc D5c '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1 \xe2\x80\x94 **From:** analysis\n\n** Non-Functional Requirements:**\n- NFR-1 \xe2\x80\x94 **From:** analysis\n')
outD5c=$(bash "$SCRIPT" "$pathD5c" 2>&1)
[ "$(summary "$outD5c" UNTAGGED)" = "1" ] && [ "$(summary "$outD5c" FROM)" = "0" ] \
    && ! printf '%s' "$outD5c" | $GREP -qF 'closed by this label' \
    && pass "D5c a leading-space opener after a valid group, correctly tagged beneath it, is FROM: 0 with no closed-by-this-label misattribution" \
    || fail "D5c a leading-space opener after a valid group, correctly tagged beneath it, is FROM: 0 with no closed-by-this-label misattribution" \
         "untagged=$(summary "$outD5c" UNTAGGED) from=$(summary "$outD5c" FROM) :: $outD5c"

# D5d: whitespace on BOTH sides of the label at once.
assert_fields "D5d a both-sides-padded opener warns once" \
    '## 3. Implementation Context\n\n** Functional Requirements :**\n- untagged one\n' \
    0 0 0 1

# D5e: the exact valid form (zero padding either side) must still take the valid path and
# raise no opener warning at all — the widened near-miss regex (`[ \t]*` on both sides, zero
# or more) mathematically also matches zero spaces, so this pins that the valid branch, tested
# first in the if/else-if chain, always wins that case and the near-miss branch is never even
# reached for it.
assert_fields "D5e the exact valid form still takes the valid path, no opener warning" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1 \xe2\x80\x94 **From:** analysis\n' \
    0 0 0 0

# D5f (was_req has no case): a generic, non-requirement bold label (Context Files) with NO
# requirement group open before it at all — was_req is false the instant this line is seen, so
# req_close_loc must stay unset. A misplaced From: tag on the bullet beneath it must therefore
# read "outside a requirement group", not "closed by this label" — Context Files closed
# nothing here because nothing was open. Every existing case pairing a generic label with a
# misplaced tag (M3, H6b) puts that label AFTER a genuinely open group, so was_req is
# legitimately true in all of them; none exercises it being false while a misplaced tag still
# follows. "analysis" is a valid VALUE deliberately, so the only thing under test is
# PLACEMENT, not value validity.
pathD5f=$(doc D5f '## 3. Implementation Context\n\n**Context Files:**\n- path/to/file \xe2\x80\x94 **From:** analysis\n')
outD5f=$(bash "$SCRIPT" "$pathD5f" 2>&1)
reasonD5f=$(printf '%s\n' "$outD5f" | $AWKBIN -F'\t' '/^  /{print $3; exit}')
[ "$(summary "$outD5f" FROM)" = "1" ] && [ "$(summary "$outD5f" UNTAGGED)" = "0" ] \
    && [ "$reasonD5f" = "From: label outside a requirement group" ] \
    && pass "D5f a generic label with no group open before it attributes a misplaced tag to absence, not to closing a label" \
    || fail "D5f a generic label with no group open before it attributes a misplaced tag to absence, not to closing a label" \
         "from=$(summary "$outD5f" FROM) untagged=$(summary "$outD5f" UNTAGGED) reason='$reasonD5f' :: $outD5f"

# D8: eighth round of the same class — D5 widened the three requirement-group-opener regexes
# to accept whitespace on either side of the label, citing FIELD_PATTERN's name.strip() in
# markdown_parser.py, but left the From: label — the one C3 is actually about — at an exact-
# spelling-only match. All four of **From:**, ** From:**, **From :**, and ** From :** open a
# FIELD_PATTERN line and break _collect_bullets() identically in production; only the first
# was recognised here. Fixed structurally via field_label(), the one function every label site
# (group openers, the From: discriminator, the occurrence split, both misplaced tests, and the
# generic-label branch) now decides from, so fixing one label spelling and missing another
# stops being possible.

# H6a (reference, reusing $outH6a/$reasonH6a from above): the exact, unpadded form's own
# numbers and reason — FROM: 1 (C3, "must be inline"), UNTAGGED: 2 (the two bullets below,
# since the From: label neither opens nor closes the group). D8a-d below must reproduce these
# exact numbers for the padded spellings, and D8e compares the reason text directly.

# D8a: leading space inside **...**.
pathD8a=$(doc D8a '## 3. Implementation Context\n\n**Functional Requirements:**\n** From:** analysis\n- untagged one\n- untagged two\n')
outD8a=$(bash "$SCRIPT" "$pathD8a" 2>&1)
reasonD8a=$(printf '%s\n' "$outD8a" | $AWKBIN -F'\t' '/^  /{if ($3 ~ /must be inline/) {print $3; exit}}')
[ "$(summary "$outD8a" FROM)" = "1" ] && [ "$(summary "$outD8a" UNTAGGED)" = "2" ] && [ -n "$reasonD8a" ] \
    && pass "D8a a leading-space-padded From: label opening its own line is caught as misplaced (C3)" \
    || fail "D8a a leading-space-padded From: label opening its own line is caught as misplaced (C3)" \
         "FROM=$(summary "$outD8a" FROM) UNTAGGED=$(summary "$outD8a" UNTAGGED) reason='$reasonD8a' :: $outD8a"

# D8b: trailing space inside **...** (space before the colon).
pathD8b=$(doc D8b '## 3. Implementation Context\n\n**Functional Requirements:**\n**From :** analysis\n- untagged one\n- untagged two\n')
outD8b=$(bash "$SCRIPT" "$pathD8b" 2>&1)
reasonD8b=$(printf '%s\n' "$outD8b" | $AWKBIN -F'\t' '/^  /{if ($3 ~ /must be inline/) {print $3; exit}}')
[ "$(summary "$outD8b" FROM)" = "1" ] && [ "$(summary "$outD8b" UNTAGGED)" = "2" ] && [ -n "$reasonD8b" ] \
    && pass "D8b a trailing-space-padded From: label opening its own line is caught as misplaced (C3)" \
    || fail "D8b a trailing-space-padded From: label opening its own line is caught as misplaced (C3)" \
         "FROM=$(summary "$outD8b" FROM) UNTAGGED=$(summary "$outD8b" UNTAGGED) reason='$reasonD8b' :: $outD8b"

# D8c: both sides padded.
pathD8c=$(doc D8c '## 3. Implementation Context\n\n**Functional Requirements:**\n** From :** analysis\n- untagged one\n- untagged two\n')
outD8c=$(bash "$SCRIPT" "$pathD8c" 2>&1)
reasonD8c=$(printf '%s\n' "$outD8c" | $AWKBIN -F'\t' '/^  /{if ($3 ~ /must be inline/) {print $3; exit}}')
[ "$(summary "$outD8c" FROM)" = "1" ] && [ "$(summary "$outD8c" UNTAGGED)" = "2" ] && [ -n "$reasonD8c" ] \
    && pass "D8c a both-sides-padded From: label opening its own line is caught as misplaced (C3)" \
    || fail "D8c a both-sides-padded From: label opening its own line is caught as misplaced (C3)" \
         "FROM=$(summary "$outD8c" FROM) UNTAGGED=$(summary "$outD8c" UNTAGGED) reason='$reasonD8c' :: $outD8c"

# D8d: crossed with indentation — H6a's own shape (an indented From: label) PLUS internal
# padding at once, since field_label() strips the line edges and the label padding in the
# same normalisation and a bug isolated to only one axis would not show up testing them apart.
pathD8d=$(doc D8d '## 3. Implementation Context\n\n**Functional Requirements:**\n  ** From:** analysis\n- untagged one\n- untagged two\n')
outD8d=$(bash "$SCRIPT" "$pathD8d" 2>&1)
reasonD8d=$(printf '%s\n' "$outD8d" | $AWKBIN -F'\t' '/^  /{if ($3 ~ /must be inline/) {print $3; exit}}')
[ "$(summary "$outD8d" FROM)" = "1" ] && [ "$(summary "$outD8d" UNTAGGED)" = "2" ] && [ -n "$reasonD8d" ] \
    && pass "D8d indentation crossed with internal padding is still caught as misplaced (C3)" \
    || fail "D8d indentation crossed with internal padding is still caught as misplaced (C3)" \
         "FROM=$(summary "$outD8d" FROM) UNTAGGED=$(summary "$outD8d" UNTAGGED) reason='$reasonD8d' :: $outD8d"

# D8e: the widening has not collapsed the exact and padded forms into different, possibly
# wrong, reasons — both go through the identical C3 branch now, so their reason text must be
# byte-identical to the exact form's (H6a), not merely "also contains must be inline".
[ -n "$reasonH6a" ] && [ "$reasonD8a" = "$reasonH6a" ] && [ "$reasonD8b" = "$reasonH6a" ] \
    && [ "$reasonD8c" = "$reasonH6a" ] && [ "$reasonD8d" = "$reasonH6a" ] \
    && pass "D8e the exact and every padded From: opener form report the identical C3 reason text" \
    || fail "D8e the exact and every padded From: opener form report the identical C3 reason text" \
         "exact='$reasonH6a' a='$reasonD8a' b='$reasonD8b' c='$reasonD8c' d='$reasonD8d'"

# D8f: the inline case — a padded tag mid-bullet is not recognised as a tag AT ALL under the
# old exact-only occurrence split, downgrading FROM: 1 (a value that needs fixing) to
# UNTAGGED: 1 (a bullet that predates the field entirely) — the wrong signal for triage. The
# reviewer pairing constraint: this also proves the occurrence split and the untagged "n <= 1"
# test cannot disagree, since both derive from the SAME split() call — if they could, this
# bullet would show FROM: 1 AND UNTAGGED: 1 at once (double-counted), not FROM: 1 alone.
assert_fields "D8f an inline padded From: tag is recognised as a tag, with an unrecognised value, not read as untagged" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1: alpha \xe2\x80\x94 **From :** hunch\n' \
    0 0 1 0

# D8g: the group-opener labels under the SAME padding axis D7 added (wide Unicode whitespace,
# not just [ \t]) still behave, now that they read through field_label() too — an NBSP
# (U+00A0) directly after ** must still be recognised as the near-miss, not silently swallowed
# by the generic "other bold label" branch the way an unrecognised padding form always was.
assert_fields "D8g an NBSP-padded group-opener label is still recognised as the near-miss opener" \
    '## 3. Implementation Context\n\n**\xc2\xa0Functional Requirements:**\n- untagged one\n' \
    0 0 0 1

# H1 (round 3): a §3 with no requirement bullets at all — prose only, no bold label, no list
# item — must report zero on all four counters, not UNTAGGED: 1. Before this fix the section
# sentinel fired unconditionally whenever no group was ever recognised, with no way to tell
# "malformed attempt" (a bullet is there, nothing recognised it) apart from "nothing attempted"
# (no bullet exists for a From: tag to be missing from at all) — the same distinction a
# declared-but-empty §2 already draws by reporting 0 words rather than a ceiling breach.
assert_fields "H1 (round 3) a section 3 with no requirement bullets at all reports zero, not a false UNTAGGED warning" \
    '## 3. Implementation Context\n\nSome prose describing the module, no bullets anywhere.\n' \
    0 0 0 0

# H1 (round 3, value revised under D3): req_scan_bullets must not leak across the
# heading-transition reset. Section 1 leaves a valid Functional Requirements group OPEN at its
# close (no closing label inside it), so req_scan_bullets is 1 the instant the section ends.
# Section 2 is a second slot-3-canon heading whose only content is an untagged bullet under NO
# label of any kind — not even a malformed one. Before D3, a leaked req_scan_bullets == 1 would
# have double-flagged that bullet on top of the (also since-removed) section-level sentinel;
# under D3, an arbitrary bullet with no group-opener attempt behind it is not itself a defect
# (the fix's own second half — see the Context Files case below), so the correct total is 0,
# not 1. This fixture still earns its keep as the req_scan_bullets-reset case: if the reset
# leaked, section 2's bullet WOULD be individually flagged, so a leak still turns this red.
assert_fields "H1 (round 3, revised) req_scan_bullets does not leak from an unclosed valid group into the next slot-3 section" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** ticket 464\n\n## More Implementation Context\n\n- untagged bullet\n\n## 4. Architecture Overview\n\nmore text\n' \
    0 0 0 0

# H1 (round 3): slot3_bullet_ever must not leak across close_slot3_section()'s own reset
# either. Section 1 has a malformed (heading-level) opener with one bullet — the sentinel
# fires once, correctly. Section 2 is a second slot-3-canon heading with NO bullet at all — if
# slot3_bullet_ever leaked in as 1 from section 1, the "no requirement bullets at all" fix
# above would be defeated the moment a §3 with real content precedes an empty one, which is
# the common case (design.md always opens with a real §3 before any coincidental heading match
# further down).
assert_fields "H1 (round 3) slot3_bullet_ever does not leak into a following bullet-less slot-3 section" \
    '## 3. Implementation Context\n\n#### Functional Requirements\n- untagged one\n\n## Extra Implementation Context\n\nJust prose here, no bullets at all.\n\n## 4. Architecture Overview\n\nmore text\n' \
    0 0 0 1

# H1 (round 3), "Also fix": req_close_loc must not leak from one slot-3 section into the next
# either — this reset already existed in close_slot3_section() before this round, but no
# fixture exercised two slot-3 sections, so deleting it left the suite fully green. Section 1
# opens validly and is closed by a **Context Files:** label, which records req_close_loc so a
# LATER stray tag in the same section would be attributed to that label. Section 2 is a fresh
# slot-3-canon heading with a misplaced From: tag under no group at all — if req_close_loc
# leaked in from section 1, the hit would be wrongly attributed to section 1's Context Files
# label instead of correctly reporting "outside a requirement group".
pathRCL=$(doc reqcloseloc '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** ticket 464\n\n**Context Files:**\n- path/to/file\n\n## Extra Implementation Context\n\n- bullet text **From:** hunch\n')
outRCL=$(bash "$SCRIPT" "$pathRCL" 2>&1)
detailRCL=$(printf '%s\n' "$outRCL" | $AWKBIN -F'\t' '/^  / && $3 ~ /outside a requirement group/ {print $2 "\t" $3; exit}')
[ "$(summary "$outRCL" FROM)" = "1" ] \
    && [ "$detailRCL" = "bullet text **From:** hunch	From: label outside a requirement group" ] \
    && pass "H1 (round 3) req_close_loc does not leak from one slot-3 section into the next" \
    || fail "H1 (round 3) req_close_loc does not leak from one slot-3 section into the next" \
         "detail='$detailRCL' :: $outRCL"

# M2 (headline case): a validly-opened Functional Requirements group, followed by a
# spaced-colon Non-Functional Requirements group with an untagged bullet beneath it. Before
# this fix, slot3_group_ever was set by the FIRST (valid) group and stayed true for the rest
# of the section, so close_slot3_section() suppressed its warning and the untagged bullet
# under the malformed second group reported UNTAGGED: 0 — clean, despite a real requirement
# escaping the tag check entirely. The spaced-colon check above must fire independent of
# slot3_group_ever, not only when it is the sole group in the section.
assert_fields "M2 a spaced-colon group after a valid one is still reported, not suppressed by it" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** ticket 464\n\n**Non-Functional Requirements :**\n- untagged nfr\n' \
    0 0 0 1

# D3a: M2's own headline case, generalised from the spaced-colon shape to the heading-level
# one — a validly-opened Functional Requirements group, followed by a MALFORMED (H4-heading)
# Non-Functional Requirements opener whose one bullet is correctly tagged. Before D3, the H3+
# heading rule never touched UNTAGGED at all, and the section-level fallback that would
# otherwise have caught a heading-level opener was gated on "no fully-valid group ever opened
# in this section" — true here only because the FIRST group opened validly, so the malformed
# SECOND opener went completely unreported: UNTAGGED: 0, indistinguishable from a section with
# no defect at all. The correctly-tagged bullet beneath the malformed heading is deliberate: it
# proves the hit is for the opener shape itself, not a smuggled-in "missing tag" finding — FROM
# and the rest of UNTAGGED must both read 0.
assert_fields "D3a a heading-level opener after a valid group is still reported, not suppressed by it" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1: ok \xe2\x80\x94 **From:** analysis\n\n#### Non-Functional Requirements\n- NFR-1: tagged fine \xe2\x80\x94 **From:** analysis\n' \
    0 0 0 1

# D3b: a §3 carrying only a non-requirement label (Context Files) and a bullet beneath it — no
# Functional/Non-Functional/Constraints attempt anywhere, valid or malformed. Before D3, ANY
# bullet in the section — this one included, despite belonging to a label the mechanism does
# not scan for tags at all — armed the section-level fallback, and no group of any kind having
# opened made it fire: UNTAGGED: 1 on a section that never attempted the field being checked.
# D3 removed that fallback outright, so nothing here can fire: 0 across the board.
assert_fields "D3b a section carrying only Context Files and a bullet reports zero" \
    '## 3. Implementation Context\n\n**Context Files:**\n- path/to/file\n' \
    0 0 0 0

# D3c: the reviewer note attached to D3 — close_slot3_section()'s old comment claimed every
# malformed-opener shape "has a bullet beneath it by construction", which was false for a
# section whose requirements are written as a table instead of a bulleted list. Under the OLD
# mechanism this reported UNTAGGED: 0 even under a malformed opener, because the section-level
# fallback was gated on slot3_bullet_ever, and a table row is not a list-item bullet. D3's
# heading-level detection fires the instant the malformed heading line itself is seen — before
# anything below it is scanned — so it does not matter whether a bullet ever follows at all.
assert_fields "D3c a heading-level opener is reported even when its requirements are table rows, not bullets" \
    '## 3. Implementation Context\n\n#### Functional Requirements\n\n| req | tag |\n|---|---|\n| FR-1 | analysis |\n' \
    0 0 0 1

# D3d: a bulleted-label opener is itself also a list-item bullet, so mutation-testing the fix
# surfaced a double-count hazard neither U28b nor D3a-c happens to exercise: if a VALID group
# opened earlier in the section is left unclosed (req_scan_bullets still 1, leaked forward, the
# same shape H1/round-3's req_scan_bullets-leak case already covers for the ordinary bullet
# case), a SUBSEQUENT bulleted-malformed-opener line for a DIFFERENT field also matches the
# per-bullet "no From: tag" regex — it starts with a list marker and carries no **From:** — so
# without excluding bulleted_open there it would be counted TWICE: once as the malformed
# opener, once again as an untagged bullet. FR-1 is validly tagged and closed by nothing before
# the NFR opener, so only the opener itself may fire; the FR-2 bullet after it is tagged too, so
# it must not fire either.
assert_fields "D3d a bulleted opener under a still-open earlier group is counted once, not twice" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- FR-1 \xe2\x80\x94 **From:** ticket 464\n- **Non-Functional Requirements:**\n- FR-2 \xe2\x80\x94 **From:** analysis\n' \
    0 0 0 1

# D3e: the negative counterpart the H3+ heading rule needs — an ordinary, unrelated H3+
# sub-heading inside a fully-tagged §3 must NOT trip the malformed-opener detection. The
# heading-level check is deliberately narrow (h3 ~ the three field names, with or without a
# trailing colon) precisely so a real sub-heading like "### Background" is not mistaken for a
# malformed Functional/Non-Functional/Constraints opener — without that narrowing, any H3+ in
# slot 3 would warn, and no OTHER case here happens to exercise a non-matching heading text
# (they all either omit the H3+ line entirely or use one of the three field names verbatim).
assert_fields "D3e an unrelated H3+ sub-heading in a fully-tagged section 3 is not flagged" \
    '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** ticket 464\n\n### Background\n\nsome prose explaining context.\n' \
    0 0 0 0

# D3f: the bulleted_open counterpart to D3e — a bulleted, non-requirement bold label ("-
# **Context Files:**") must not be mistaken for a bulleted requirement-group opener. Section
# opens fresh (req_scan_bullets starts at 0, so the pre-existing per-bullet sweep cannot also
# be the thing keeping this clean — that would test something else) so only the bulleted_open
# regex specificity is on the line: it names the three requirement labels explicitly, not any
# bulleted bold label.
assert_fields "D3f a bulleted Context Files label is not mistaken for a bulleted requirement opener" \
    '## 3. Implementation Context\n\n- **Context Files:**\n- path/to/file\n' \
    0 0 0 0

# D3g: the heading-level check is gated on canon(sec) == "3" for the same reason field_scan
# itself is (slot != "3" return) — a heading that happens to share text with one of the three
# field labels means nothing outside section 3. A §5 sub-heading literally titled "Functional
# Requirements" (describing, say, functional requirements the DESIGN satisfies, not a §3
# requirement group) must not be flagged just because the label text matches; only D3e (an
# H3+ heading INSIDE §3 with unrelated text) exercises the h3 regex specificity, and only D3a/
# c exercise canon(sec) == "3" being true — none of them exercises it being FALSE while the
# regex would otherwise match.
assert_fields "D3g a heading matching a requirement-group label outside section 3 is not flagged" \
    '## 5. Detailed Design\n\nsome prose\n\n### Functional Requirements\n\nmore prose\n' \
    0 0 0 0

# H1: close_slot3_section() on the section-change branch (/^##?[ \t]/) was left unguarded —
# U28a/U28b/U28c and H6c above all end the document at EOF, in §3, so only END's call site
# ever ran. Every real design.md has §3 followed by §4, so a call site exercised only at END
# is a silent hole for the shape that actually occurs in production. This fixture ends §3 at
# a `## 4.` heading instead of EOF, so only the section-change close_slot3_section() call can
# close it.
fxH1=$(doc H1boundary '## 3. Implementation Context\n\n#### Functional Requirements\n- untagged one\n\n## 4. Architecture Overview\n\nsome text here\n')
outH1=$(bash "$SCRIPT" "$fxH1" 2>&1)
[ "$(summary "$outH1" UNTAGGED)" = "1" ] \
    && pass "H1 a slot-3 section closed by a following heading is still closed, at the section-change branch" \
    || fail "H1 a slot-3 section closed by a following heading is still closed, at the section-change branch" "$outH1"

# H3 (round 3): close_slot3_section()'s internal `slot3_group_ever = 0` reset, not merely the
# call site H1 above exercises. Section 1 opens a VALID Functional Requirements group and is
# clean; section 2 is a second slot-3-canon heading whose Functional Requirements opener is
# malformed (heading level), with one untagged bullet beneath it — reachable ONLY through
# close_slot3_section()'s section-level fallback. If slot3_group_ever leaks true from section
# 1's valid group instead of resetting, the fallback for section 2 never fires: UNTAGGED stays
# 0 instead of 1, and the detail block loses its line, exactly the shape the slot-7 twin (H2,
# below) exists to catch on the other closer.
fxH3s3=$(doc H3slot3reset '## 3. Implementation Context\n\n**Functional Requirements:**\n- item \xe2\x80\x94 **From:** ticket 464\n\n## More Implementation Context Details\n\n#### Functional Requirements\n- untagged one\n\n## 4. Architecture Overview\n\nsome text here\n')
outH3s3=$(bash "$SCRIPT" "$fxH3s3" 2>&1)
detailH3s3=$(printf '%s\n' "$outH3s3" | $AWKBIN -F'\t' '/^  /{s=$1; sub(/^  /,"",s); print s; exit}')
[ "$(summary "$outH3s3" UNTAGGED)" = "1" ] \
    && [ "$detailH3s3" = "More Implementation Context Details" ] \
    && pass "H3 (round 3) close_slot3_section()'s slot3_group_ever reset does not leak across two slot-3 sections" \
    || fail "H3 (round 3) close_slot3_section()'s slot3_group_ever reset does not leak across two slot-3 sections" \
         "untagged=$(summary "$outH3s3" UNTAGGED) detail_sec='$detailH3s3' :: $outH3s3"

# H5 (round 3, wording revised under D3): the widened UNTAGGED summary wording (M11 in an
# earlier round) had no exact assertion — reverting it to the old bullet-only wording left the
# suite fully green, since every existing case only checked the numeric counter. Assert the
# full line, using a non-bullet hit (the spaced-colon opener above), so the summary provably
# describes THIS hit rather than merely containing a substring that also happens to appear in
# the old wording. D3 dropped the "group-less section(s)" category from the wording along with
# the section-level sentinel that produced it (see close_slot3_section()), so the text this
# case pins is the post-D3 wording, not M11's.
pathH5wording=$(doc H5wording '## 3. Implementation Context\n\n**Functional Requirements :**\n- untagged bullet\n')
outH5wording=$(bash "$SCRIPT" "$pathH5wording" 2>&1)
printf '%s' "$outH5wording" | $GREP -qF 'UNTAGGED: 1 requirement bullet(s) with no From tag, or malformed requirement-group opener(s)' \
    && pass "H5 (round 3) the UNTAGGED summary line carries the widened wording, exact text, for a non-bullet hit" \
    || fail "H5 (round 3) the UNTAGGED summary line carries the widened wording, exact text, for a non-bullet hit" "$outH5wording"

# M3: the per-file wrapper's TOTAL-row test used to pipe the captured output into `grep -q`,
# which exits the instant it matches — early, since TOTAL prints near the top of the output.
# Once the design-field detail block that follows pushes the remainder past the 64 KiB pipe
# buffer, the still-writing printf on the other end gets SIGPIPE (141 under `pipefail`), and
# the wrapper misreads a real, valid measurement as "no table produced".
#
# M7: 800 bullets cleared the buffer by only ~10 KB, so SIGPIPE delivery was a scheduling
# race — the mutant (reverting the here-string fix back to a `printf | grep -q` pipe) survived
# 2/25 and 2/30 runs in two independent measurements, flip zone 760-800 bullets. 7500 bullets
# measured ~696 KB of post-TOTAL output here, an order of magnitude past the 64 KiB buffer, and
# the test also asserts that margin directly — measuring the actual post-TOTAL byte count,
# not trusting the bullet count to keep producing enough of it — so a later shortening of a
# reason string or the opening_words() cap cannot silently disarm the guard without the
# assertion itself catching the shrink.
body='## 3. Implementation Context\n\n**Functional Requirements:**\n'; i=0
while [ $i -lt 7500 ]; do body="${body}- untagged bullet number $i\n"; i=$((i+1)); done
path=$(doc bigdetail "$body")
out=$(bash "$SCRIPT" "$path" 2>&1); rc=$?
post_total_bytes=$(printf '%s' "$out" | $AWKBIN 'BEGIN{f=0} /^TOTAL[ \t]/{f=1; next} f{print}' | wc -c)
[ $rc -eq 0 ] && [ "$(summary "$out" UNTAGGED)" = "7500" ] && [ "$post_total_bytes" -gt 655360 ] \
    && pass "M3 a detail block that measurably clears the pipe buffer by an order of magnitude still exits 0" \
    || fail "M3 a detail block that measurably clears the pipe buffer by an order of magnitude still exits 0" \
         "rc=$rc post_total_bytes=$post_total_bytes (want > 655360) :: $(printf '%s' "$out" | tail -2)"

# I1: the shipped template is the mechanism's own dogfood case — every Cost:/Misses: field
# is present and every requirement bullet carries a real From: tag.
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)/platforms/claude/skills/workflows/planning/DESIGN-TEMPLATE.md"
out=$(bash "$SCRIPT" "$TEMPLATE" 2>&1)
[ "$(summary "$out" COST)" = "0" ] && [ "$(summary "$out" MISSES)" = "0" ] \
    && [ "$(summary "$out" FROM)" = "0" ] && [ "$(summary "$out" UNTAGGED)" = "0" ] \
    && pass "I1 the shipped DESIGN-TEMPLATE.md reports zero on all four design-field counters" \
    || fail "I1 the shipped DESIGN-TEMPLATE.md reports zero on all four design-field counters" "$out"

# I6: the five From: values are declared once in DESIGN-TEMPLATE.md §3 guidance; the script
# owns the accepted set. Extraction is bound to the "Five values" line alone — the same
# paragraph carries an earlier `From:` mention (excluded here by starting uppercase, unlike
# every real value) and the adjacent decision-vs-analysis line carries `analysis` again plus
# `assumption`, which a read of every backtick token in the guidance would miscount as a
# sixth value.
#
# H2: script_values used to be a hardcoded literal in this test, not a read of the script —
# so a sixth value added to from_valid() alone left this assertion green while the template
# still documented five and the script accepted six, exactly the drift I6 exists to catch.
#
# D4: from_valid() no longer spells its accepted values out as literals at all — it tests
# array membership against from_first[], built in BEGIN from one declared "token:kind" list
# (see the "D4:" comment above FROM_N in platforms/claude/scripts/doc-metrics.sh). Extracting
# from from_valid()'s own body, as this test did before, would now find nothing: this reads
# that ONE declaration line instead, anchored on the literal "analysis:" so a comment or an
# unrelated split() call elsewhere in the script cannot feed it. The cardinality check mirrors
# the detector-list one above it: if the anchor ever matched twice, silently reading whichever
# one grep saw first would hide a real duplicate-declaration bug instead of failing on it.
sc_from_n=$($GREP -c 'split("analysis:[^"]*"' "$SCRIPT")
if [ "$sc_from_n" != "1" ]; then
    fail "I6 the From: token declaration appears exactly once in the script" "found $sc_from_n"
else
    pass "I6 the From: token declaration appears exactly once in the script"
fi
script_values=$($GREP -o 'split("analysis:[^"]*"' "$SCRIPT" \
    | /usr/bin/sed 's/^split("//; s/"$//' | tr ' ' '\n' | sed 's/:.*$//' | sort -u)
tmpl_line=$($GREP -m1 -F 'Five values,' "$TEMPLATE")
if [ -z "$tmpl_line" ]; then
    fail "I6 the From: value list in DESIGN-TEMPLATE.md agrees with the script's accepted set" \
         "no 'Five values,' line found in $TEMPLATE"
elif [ -z "$script_values" ]; then
    fail "I6 the From: value list in DESIGN-TEMPLATE.md agrees with the script's accepted set" \
         "extracted no accepted values from the FROM_L declaration in $SCRIPT — extraction is broken"
else
    tmpl_values=$(printf '%s' "$tmpl_line" | $GREP -oE '`[a-z]+' | tr -d '`' | sort -u)
    if [ "$tmpl_values" = "$script_values" ]; then
        pass "I6 the From: value list in DESIGN-TEMPLATE.md agrees with the script's accepted set"
    else
        fail "I6 the From: value list in DESIGN-TEMPLATE.md agrees with the script's accepted set" \
             "$(diff <(printf '%s\n' "$tmpl_values") <(printf '%s\n' "$script_values"))"
    fi
fi

# M9 (structural, revised under D4): from_valid() no longer contains any accepted first-token
# literal at all, so I6's old defence — grep the window for quoted tokens — has nothing left to
# extract a smuggled-in value FROM. D4 moved the accepted set to array membership
# (`first in from_first`); the only legitimate regex match (~) left anywhere in the window is
# `w[2] ~ /date-format/`, testing the SECOND token's shape for the "date" kind, never whether a
# first token is accepted. So: count every `~` in the window, count every `~` immediately
# preceded by `w[2]`, and require them equal. Any OTHER `~` — however it is spelled — is a
# first-token acceptance test smuggled in outside the declared array. This single structural
# rule replaces the previous enumerated one (`first ~` / `w[1] ~`) and, unlike it, also catches
# `tolower(first) ~ /^postmortem$/`: wrapping `first` in a function call defeated the old guard,
# which anchored on the literal token `first` immediately followed by `~`, but it still adds a
# tilde this window does not otherwise have, so the count comparison catches it regardless of
# how the first token is spelled or wrapped. A comment inside the window carrying a bare `~`
# would also produce a false red here — fail-safe, same as the enumerated form before it.
window_text=$(awk '
    /function from_valid\(/ { f = 1 }
    f { print }
    f && /^      }/ { exit }
' "$SCRIPT")
total_tilde=$(printf '%s\n' "$window_text" | $GREP -o '~' | wc -l | tr -d ' ')
w2_tilde=$(printf '%s\n' "$window_text" | $GREP -oE 'w\[2\][ \t]*~' | wc -l | tr -d ' ')
if [ "$total_tilde" = "$w2_tilde" ]; then
    pass "M9 the from_valid() window makes no regex-match comparison beyond the w[2] date check"
else
    fail "M9 the from_valid() window makes no regex-match comparison beyond the w[2] date check" \
         "$total_tilde total ~ but only $w2_tilde prefixed by w[2] — a first-token acceptance test is being smuggled in outside the declared array, however it is spelled"
fi

echo
# Fixed assertions, excluding the per-interpreter agreement ones and this check itself.
total=$((PASS + FAIL - nawk))
[ $total -eq "$EXPECTED_TESTS" ] \
    && pass "all $EXPECTED_TESTS fixed assertions ran (plus $nawk interpreter comparisons)" \
    || fail "all $EXPECTED_TESTS fixed assertions ran" "ran $total — a block skipped itself or EXPECTED_TESTS is stale"
[ "$SKIP" -eq 0 ] \
    && pass "no assertion was skipped" \
    || fail "no assertion was skipped" "$SKIP skipped — the property they name is unverified on this box"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
