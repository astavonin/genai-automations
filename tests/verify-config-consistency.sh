#!/usr/bin/env bash
# verify-config-consistency.sh — cross-file invariants for the Claude config corpus.
#
# The config is a pointer graph: a rule lives in one file and other files point at it. Two
# failure modes follow, and neither is visible in a diff:
#
#   1. A pointer stops resolving. `git diff` cannot show this at all when the target is a
#      directory — git does not track empty directories, so a `references/` pointer at an
#      emptied directory appears in no diff.
#   2. Two declared copies of one rule drift apart. This has happened: a phase procedure
#      ordered a blind `projctl sync pull` for months after the command file replaced it
#      with a drift check, because nothing compared them.
#
# Scope is deliberately narrow — `Read <path>` directives and the one severity table that
# names its own mirrors. A guard over every `~/.claude/...` token in the corpus is red on
# false positives: several are runtime-created, deliberately empty, or literal placeholders.
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

GREP=/usr/bin/grep
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE="$ROOT/platforms/claude"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }

# Paths that legitimately do not resolve inside the repo mirror.
#   plans/            — created by the harness at runtime; start.md probes it with 2>/dev/null
#   agent-memory/     — live per-agent memory content, never backed up (may hold proprietary notes)
#   projects/.../     — a literal ellipsis in prose, not a path
#   memory/           — .gitignore'd: "Auto-memory (may contain proprietary information)"
is_exempt() {
    case "$1" in
        plans|plans/*|agent-memory|agent-memory/*|memory|memory/*) return 0 ;;
        *"..."*|*"<"*) return 0 ;;
        *) return 1 ;;
    esac
}

echo "== Read-pointer resolution =="

# Every `Read ~/.claude/<path>` in the corpus must resolve to a non-empty file or a
# non-empty directory under platforms/claude/. This is the guard the compaction needs:
# it replaced restatements with pointers, so an unresolvable pointer is now the way a
# rule goes missing, and it goes missing silently — the reader just finds nothing.
missing=""
checked=0
while IFS= read -r target; do
    rel=${target#\~/.claude/}
    is_exempt "$rel" && continue
    checked=$((checked + 1))
    path="$CLAUDE/$rel"
    if [ -d "$path" ]; then
        [ -n "$(ls -A "$path" 2>/dev/null)" ] || missing="$missing$target (empty directory)\n"
    elif [ -f "$path" ]; then
        [ -s "$path" ] || missing="$missing$target (empty file)\n"
    else
        missing="$missing$target (absent)\n"
    fi
done < <($GREP -rhoE '(^|[[:space:]])Read ~/\.claude/[A-Za-z0-9_./-]+' \
             --include='*.md' "$CLAUDE" | sed -E 's/.*Read //' | sort -u)

if [ "$checked" -eq 0 ]; then
    fail "Read pointers resolve" "extracted no pointers — the extraction regex is broken"
elif [ -z "$missing" ]; then
    pass "all $checked distinct Read pointers resolve to non-empty targets"
else
    fail "all $checked distinct Read pointers resolve to non-empty targets" "$(printf "%b" "$missing")"
fi

# The D4 shape: a skill says "See `references/` ..." and that directory holds nothing, so
# the path resolves and the reader is sent to an empty room. An empty references/ with no
# pointer at it is clutter, not a defect — git does not track empty directories, so several
# exist only in the working tree. Test the pair, not the directory alone.
dangling=""
while IFS= read -r skill; do
    $GREP -qE '(See|see) `references/`|references/ directory' "$skill" || continue
    refs="$(dirname "$skill")/references"
    [ -d "$refs" ] || { dangling="$dangling$skill → references/ (absent)\n"; continue; }
    [ -n "$(ls -A "$refs" 2>/dev/null)" ] || dangling="$dangling$skill → references/ (empty)\n"
done < <(find "$CLAUDE" -name 'SKILL.md')

if [ -z "$dangling" ]; then
    pass "every skill pointing at references/ has a non-empty one"
else
    fail "every skill pointing at references/ has a non-empty one" "$(printf "%b" "$dangling")"
fi

echo "== Declared mirror agreement =="

# regression-test/SKILL.md → "Review Severities" names its own mirrors and states that a
# severity disagreeing across copies makes Claude and Codex reach different verdicts inside
# the same review. It is the one rule in the config that documents its duplication; assert
# what it asserts about itself.
sev_rows() {   # emit the "| condition | severity |" rows of the severity table
    $GREP -E '^\| .+ \| (Critical|High|Medium|Low) \|$' "$1" | sed 's/[[:space:]]\+/ /g' | sort
}

SRC="$CLAUDE/skills/workflows/regression-test/SKILL.md"
MIRROR="$CLAUDE/skills/domains/quality-attributes/references/review-checklist.md"

src_rows=$(sev_rows "$SRC")
mirror_rows=$(sev_rows "$MIRROR")
n_src=$(printf '%s\n' "$src_rows" | $GREP -c . || true)

if [ "$n_src" -eq 0 ]; then
    fail "severity table found in regression-test/SKILL.md" "extracted no rows"
elif [ "$src_rows" = "$mirror_rows" ]; then
    pass "severity table ($n_src rows) is identical in regression-test and review-checklist"
else
    fail "severity table ($n_src rows) is identical in regression-test and review-checklist" \
         "$(diff <(printf '%s\n' "$src_rows") <(printf '%s\n' "$mirror_rows") | head -12)"
fi

echo "== Command roster =="

# CLAUDE.md classifies commands rather than listing them, but it names the eight phase
# commands inline. Each must exist, or a phase has no entry point.
phase_cmds="start research design review-design implement review-code verify complete"
absent=""
for c in $phase_cmds; do
    [ -f "$CLAUDE/commands/$c.md" ] || absent="$absent /$c"
done
if [ -z "$absent" ]; then
    pass "all 8 phase commands named in CLAUDE.md exist under commands/"
else
    fail "all 8 phase commands named in CLAUDE.md exist under commands/" "missing:$absent"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
