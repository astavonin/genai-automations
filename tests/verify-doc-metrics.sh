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
EXPECTED_TESTS=161

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
bad=$(printf '%s\n' "$out" | $AWKBIN -F'\t' '/^[^ =]/ && !/^REGISTER|^CEILING|^UNSLOTTED|^register hits/ {if (NF != 7) c++} END {print c+0}')
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
        if printf '%s' "$got" | $GREP -q 'register hits' && [ "$(summary "$got" REGISTER)" -gt 5 ]; then
            reference="$got"; pass "$A produced a non-empty baseline"
        else
            fail "$A produced a non-empty baseline" "$got"; break
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
