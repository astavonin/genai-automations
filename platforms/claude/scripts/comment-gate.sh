#!/usr/bin/env bash
# comment-gate.sh — measure added body-comment density per changed file, plus four
# per-line flag scans, over the diff against a resolved base.
#
# The gate mechanizes a position rule, not a content judgment (see
# skills/domains/code-quality/SKILL.md → Comment Policy): a comment preceding a declaration
# or opening a test is the required class and is excluded; a comment inside a function body
# is priced as a body comment. The four flags catch what the ratio cannot see, because each
# is a property of one comment rather than of the file's proportions: a suppression marker
# with no reason, a `TODO`/`FIXME` with no ticket, a body-comment run past
# MAX_COMMENT_RUN, and a comment citing a gitignored planning document.
#
# Usage:   comment-gate.sh <base-ref>
#
# Exit codes:
#   0    the scan ran — the verdict is in the output (PASS/WARN/BLOCK/small/skip, per file)
#   1    BLOCKER — the scan did not run, or did not run cleanly: no <base-ref>, not a git
#        repo, unresolvable base, the awk interpreter is absent/not executable, mktemp
#        failed, or the classifier died mid-file (a present-but-broken interpreter, a file
#        it could not tokenise) without emitting its per-file result
#
# Exit status never encodes a verdict, so callers must read the output rather than wiring
# && to it — a BLOCK does not change the exit code.
#
# Tests: tests/verify-comment-gate.sh in the genai-automations repo (not installed alongside
#        this script; run it there after editing).

set -uo pipefail

# Constants (NFR-1): guessed now, tuned later against evidence. Named so a future tuning
# pass edits one line each, not a scattered literal.
WARN_THRESHOLD=10
BLOCK_THRESHOLD=25
MIN_ADDED_CODE=10
# Longest body-comment run that is not flagged. 2 mirrors the one-or-two-lines rule in
# agents/coder.md; a longer WHY is the signal to extract a named function instead.
MAX_COMMENT_RUN=2

# Interpreter seam, mirroring citation-scan.sh's CITATION_SCAN_AWK: gawk, mawk, and
# busybox awk disagree on regex extensions, so the classifier below avoids GNU-only
# features (\b, \<, \>) entirely rather than picking one implementation to trust.
AWK="${COMMENT_GATE_AWK:-awk}"
if ! command -v "$AWK" >/dev/null 2>&1; then
    echo "BLOCKER: awk interpreter not found: $AWK" >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: not a git repository" >&2
    exit 1
fi

BASE_REF="${1-}"
if [ -z "$BASE_REF" ]; then
    echo "BLOCKER: no <base-ref> argument given" >&2
    exit 1
fi
if ! git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null; then
    echo "BLOCKER: unresolvable base ref: $BASE_REF" >&2
    exit 1
fi

ROOT=$(git rev-parse --show-toplevel)

# --- the classifier: one awk program, invoked once per candidate file -------------
#
# Two ARGV files: the first (FNR==NR) is the added-line-number set (one lineno per line,
# built by the hunk parser below, or 1..N whole for an untracked file); the second is the
# working-tree file itself. Position tests (declaration-adjacent, test-head, file-head)
# read the second file's lines regardless of added-status — only the added set gates what
# enters the ratio or the flag scan.
read -r -d '' CLASSIFIER <<'AWKEOF'
function ltrim(s,   i, n, c) {
    n = length(s)
    for (i = 1; i <= n; i++) { c = substr(s, i, 1); if (c != " " && c != "\t") break }
    return substr(s, i)
}
function indent_of(s,   i, n, c) {
    n = length(s)
    for (i = 1; i <= n; i++) { c = substr(s, i, 1); if (c != " " && c != "\t") break }
    return i - 1
}
function is_blank(s) { return (ltrim(s) == "") }
function rtrim(s,    n, c) {
    n = length(s)
    while (n > 0) {
        c = substr(s, n, 1)
        if (c != " " && c != "\t") break
        n--
    }
    return substr(s, 1, n)
}

# Whole-word prefix test without \b/\< (GNU-only): the next character after the
# candidate keyword must not itself be an identifier character.
function starts_kw(s, kw,    n, nc) {
    n = length(kw)
    if (substr(s, 1, n) != kw) return 0
    if (length(s) == n) return 1
    nc = substr(s, n + 1, 1)
    return (nc !~ /[A-Za-z0-9_]/)
}

# Shared "does t start with any keyword in this space-separated list" test — one place
# for the split-and-loop pattern the declaration and disqualifier keyword sets each need,
# rather than four copies of it. Not used for the suppression markers below: those pair
# each marker with its own allowed-tail grammar, a different shape a keyword list cannot
# carry.
function matches_any_kw(t, list,    words, n, i) {
    n = split(list, words, " ")
    for (i = 1; i <= n; i++) if (starts_kw(t, words[i])) return 1
    return 0
}

function is_ctrl_disqualified(t) {
    return matches_any_kw(t, "if for while switch catch do else return throw new delete co_await co_return")
}

# The signature branch: a parameter list, a trailing { or ;, and a type/qualifier as the
# token immediately ahead of the callee — nothing before the first ( may be an assignment
# or operator. Walked with substr/index rather than one regex, since the disqualifying
# case (`total = compute(x);`) and the qualifying one (`int decode(Frame& f) {`) differ
# only in the single token immediately before the callee, which a regex cannot isolate
# portably without backreferences.
function is_signature(t,    p, rt, lastc, pre, j, remainder) {
    p = index(t, "(")
    if (p <= 1) return 0
    if (index(t, ")") == 0) return 0
    # An assignment anywhere ahead of the callee makes this an expression statement, not a
    # declaration — `auto p = new Frame(x);` has no operator immediately before its own
    # callee (`Frame`), so only a whole-prefix scan for `=` catches it.
    if (index(substr(t, 1, p - 1), "=") > 0) return 0

    rt = rtrim(t)
    lastc = substr(rt, length(rt), 1)
    if (lastc != "{" && lastc != ";") return 0

    pre = rtrim(substr(t, 1, p - 1))
    if (pre == "") return 0

    j = length(pre)
    while (j > 0 && substr(pre, j, 1) ~ /[A-Za-z0-9_:]/) j--
    if (j == length(pre)) return 0
    remainder = rtrim(substr(pre, 1, j))
    lastc = substr(remainder, length(remainder), 1)
    if (lastc ~ /[A-Za-z0-9_*&:]/) return 1
    # A templated or bracketed return type ends in `>` or `]`, neither an identifier
    # character — accepted only when its opening `<`/`[` is present earlier in the same
    # remainder, so a stray `>` from something else does not qualify a non-type token.
    if (lastc == ">" && index(remainder, "<") > 0) return 1
    if (lastc == "]" && index(remainder, "[") > 0) return 1
    return 0
}

# Declaration-shaped, read directly off the working-tree line (raw, untrimmed — indent is
# measured on it). The control-keyword disqualifier is only ever reachable by C-like
# shapes in practice (Hash's own keyword set never collides with it), so it is applied
# unconditionally rather than gated on FAMILY.
function is_decl(raw,    t, t2, ind) {
    t = ltrim(raw)
    if (t == "") return 0
    if (is_ctrl_disqualified(t)) return 0
    # A leading `}` or `)` (closing the block above) hides a disqualifying keyword that
    # starts right after it, as in `} else if (ready) {` — re-run the same test past it.
    t2 = t
    if (substr(t2, 1, 1) == "}" || substr(t2, 1, 1) == ")") t2 = ltrim(substr(t2, 2))
    if (t2 != t && is_ctrl_disqualified(t2)) return 0
    ind = indent_of(raw)
    if (FAMILY == "clike") {
        if (matches_any_kw(t, "class struct enum union namespace template interface type func fn impl trait mod pub")) return 1
        if (starts_kw(t, "#define")) return 1
        if (ind == 0 && matches_any_kw(t, "const var static using typedef constexpr")) return 1
        return is_signature(t)
    }
    if (matches_any_kw(t, "def class function readonly declare")) return 1
    if (starts_kw(t, "async def")) return 1
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)[ \t]*\{[ \t]*$/) return 1
    if (ind == 0 && t ~ /^[A-Z_][A-Z0-9_]*[ \t]*=/) return 1
    return 0
}

function is_testdecl(raw,    t) {
    t = ltrim(raw)
    if (FAMILY == "clike") {
        if (t ~ /^TEST\(/) return 1
        if (t ~ /^TEST_F\(/) return 1
        if (t ~ /^func Test/) return 1
        if (t ~ /^fn test/) return 1
        if (t ~ /^test "/) return 1
        return 0
    }
    if (t ~ /^def test/) return 1
    if (t ~ /^@test "/) return 1
    if (t ~ /^test_[A-Za-z0-9_]*\(\)/) return 1
    if (t ~ /^@pytest/) return 1
    return 0
}

# The flag half: independent of comment classification, so a trailing suppression on a
# code line is still caught, and a Rust attribute (no comment syntax at all) is too.
#
# One (marker, allowed-tail) pair per suppression family, checked in order, first match
# wins — NOLINTNEXTLINE must precede the bare NOLINT it would otherwise partially match.
# Each allowed-tail is what a marker's OWN rule-list grammar permits while still counting
# as "no reason": a colon-list for `noqa`, a bracketed code list for `type: ignore`, an
# optional rule in parens for the NOLINT family. Collapsing to one table is what
# catches `// NOLINT(bugprone-narrowing)` and `# type: ignore[arg-type]` — the seven
# hardcoded per-marker branches this replaces required a reason to be absent, but tested
# the wrong thing for "reason": zero characters after the marker itself, not zero
# characters after the marker's own permitted rule list.
function check_bare_suppression(raw,    i, n, mre, tre, rest) {
    n = 0
    n++; mre[n] = "#\\[allow\\([^)]*\\)\\]";             tre[n] = "^[ \t]*$"
    n++; mre[n] = "#[ \t]*noqa";                          tre[n] = "^([ \t]*:[ \t]*[A-Za-z0-9]+([ \t]*,[ \t]*[A-Za-z0-9]+)*)?[ \t]*$"
    n++; mre[n] = "#[ \t]*type:[ \t]*ignore";             tre[n] = "^([ \t]*\\[[A-Za-z0-9_-]+([ \t]*,[ \t]*[A-Za-z0-9_-]+)*\\])?[ \t]*$"
    n++; mre[n] = "//[ \t]*NOLINTNEXTLINE(\\([^)]*\\))?"; tre[n] = "^[ \t]*$"
    n++; mre[n] = "//[ \t]*NOLINT(\\([^)]*\\))?";         tre[n] = "^[ \t]*$"
    n++; mre[n] = "//[ \t]*nolint:[A-Za-z0-9_]+";         tre[n] = "^[ \t]*$"

    for (i = 1; i <= n; i++) {
        if (match(raw, mre[i])) {
            rest = substr(raw, RSTART + RLENGTH)
            # The documented separator between a marker's own rule-list and a free-text
            # reason is an optional trailing `:` — a tail that is just that delimiter (only
            # whitespace after it) is still "no reason", so drop it before testing what the
            # marker's own grammar allows through as empty.
            sub(/:[ \t]*$/, "", rest)
            return (rest ~ tre[i]) ? "bare-suppression" : ""
        }
    }
    return ""
}

# comment_marker_pos: where the family's first comment marker sits on a raw line, or 0 if
# the line carries none — used only to scope the `TODO`/`FIXME` grep
# to comment text; the suppression grep below stays a whole-line scan regardless.
function comment_marker_pos(raw,    p_slash, p_star) {
    if (FAMILY == "clike") {
        p_slash = index(raw, "//")
        p_star = index(raw, "/*")
        if (p_slash == 0) return p_star
        if (p_star == 0) return p_slash
        return (p_slash < p_star) ? p_slash : p_star
    }
    return index(raw, "#")
}

# check_todo: a `TODO`/`FIXME` flags only inside comment text — the
# whole line where the classifier already typed it COMMENT (a // or /* opener, or a
# /* ... */ span line), or the trailing text from the first comment marker onward where it
# typed the line CODE; a code line carrying no marker at all is not searched. A bare
# whole-line scan for these two ordinary words has no bound on false positives — they occur
# in code, in string/regex literals, and in prose about this rule, which is the defect the
# STEP-7 observed-failures ledger records and this scoping fixes.
# check_planning_ref: a comment citing a planning document or a doc section. Those files
# are globally gitignored, so no reader of a clone can resolve the pointer and no commit
# pins what it named. Scoped to comment text the same way as the TODO grep, since such a
# path in code is a legitimate operand.
function check_planning_ref(raw, ln,    scan, pos) {
    if (type[ln] == "COMMENT") {
        scan = raw
    } else {
        pos = comment_marker_pos(raw)
        if (pos == 0) return ""
        scan = substr(raw, pos)
    }
    if (scan ~ /§[ \t]*[0-9]/) return "planning-ref"
    if (scan ~ /(design|analysis|design-review|code-review|fix-review|codex-review|spec|spec-review|article-review|brief|draft|observed-failures|progress|status|overview)\.md/) return "planning-ref"
    if (scan ~ /planning\//) return "planning-ref"
    return ""
}

function check_todo(raw, ln,    scan, pos) {
    if (type[ln] == "COMMENT") {
        scan = raw
    } else {
        pos = comment_marker_pos(raw)
        if (pos == 0) return ""
        scan = substr(raw, pos)
    }
    if (scan !~ /(TODO|FIXME)/) return ""
    if (scan ~ /#[0-9]+/) return ""
    if (scan ~ /[A-Z][A-Z0-9]+-[0-9]+/) return ""
    return "todo-no-ticket"
}

BEGIN { in_span = 0; total = 0 }
FILENAME == AF { added[$1] = 1; next }
{
    raw = $0
    sub(/\r$/, "", raw)
    total = FNR
    text[FNR] = raw
    if (is_blank(raw)) { type[FNR] = "BLANK"; next }
    t = ltrim(raw)
    if (FAMILY == "clike") {
        if (in_span) {
            type[FNR] = "COMMENT"
            if (index(t, "*/") > 0) in_span = 0
        } else if (substr(t, 1, 2) == "//") {
            type[FNR] = "COMMENT"
        } else if (substr(t, 1, 2) == "/*") {
            type[FNR] = "COMMENT"
            if (index(substr(t, 3), "*/") == 0) in_span = 1
        } else {
            # A `/* ... */` opened after code on the same line: the opener line is
            # still code, but the span must still open here — otherwise every continuation
            # line mistypes as CODE, since none of them start with a comment marker either.
            op = index(raw, "/*")
            if (op > 0 && index(substr(raw, op + 2), "*/") == 0) in_span = 1
            type[FNR] = "CODE"
        }
    } else {
        type[FNR] = (substr(t, 1, 1) == "#") ? "COMMENT" : "CODE"
    }
}
END {
    # file-head boundary: the first line that is neither comment nor blank. Comment/blank
    # lines before it are excluded regardless of an internal blank (the one place a
    # blank does not close a block") — falls out for free below since the test is
    # per-line (k < H), never a blank-bounded block.
    H = total + 1
    for (i = 1; i <= total; i++) if (type[i] == "CODE") { H = i; break }

    # Maximal comment runs -> declaration-adjacent / test-head exclusion. A run can never
    # contain a blank (blank has its own type), so adjacency is strict by construction —
    # the line right after the run and the line right before it are what get tested, and
    # a blank in either position simply fails is_decl/is_testdecl on empty text.
    i = 1
    while (i <= total) {
        if (type[i] == "COMMENT") {
            s = i
            while (i <= total && type[i] == "COMMENT") i++
            e = i - 1
            below = (e + 1 <= total) ? is_decl(text[e + 1]) : 0
            above = (s - 1 >= 1) ? is_testdecl(text[s - 1]) : 0
            for (k = s; k <= e; k++) {
                ex = (k < H) || below || above
                excluded[k] = ex
            }
            # Run length is a property of the run, not of any line in it, so it is measured
            # here and reported once at the run's first added line. Excluded runs are the
            # documented class (file head, declaration, test head) and are not measured.
            if (!ex && (e - s + 1) > MAXRUN) {
                for (k = s; k <= e; k++) if (k in added) { longrun[k] = 1; break }
            }
        } else {
            i++
        }
    }

    num = 0; den = 0
    for (i = 1; i <= total; i++) {
        if (!(i in added)) continue
        if (type[i] == "BLANK") continue
        if (type[i] == "COMMENT") { if (!excluded[i]) num++ }
        else den++
    }
    print "NUM\t" num "\t" den

    for (i = 1; i <= total; i++) {
        if (!(i in added)) continue
        lbl = check_bare_suppression(text[i])
        if (lbl != "") print "FLAG\t" lbl "\t" i
        lbl = check_todo(text[i], i)
        if (lbl != "") print "FLAG\t" lbl "\t" i
        lbl = check_planning_ref(text[i], i)
        if (lbl != "") print "FLAG\t" lbl "\t" i
        if (i in longrun) print "FLAG\tlong-comment-run\t" i
    }
}
AWKEOF

# --- the hunk parser: which new-file line numbers are "+" lines --------------------
#
# Only counts lines once a hunk header (@@) has been seen, so the "diff --git"/"index"/
# "---"/"+++" preamble of a per-file diff never perturbs the new-file counter (C4).
read -r -d '' HUNK_PARSER <<'AWKEOF'
BEGIN { started = 0 }
/^@@/ {
    match($0, /\+[0-9]+/)
    newline = substr($0, RSTART + 1, RLENGTH - 1) + 0
    started = 1
    next
}
!started { next }
/^\+/ { print newline; newline++; next }
/^-/ { next }
/^\\/ { next }
{ newline++ }
AWKEOF

TMPDIR_ROOT=$(mktemp -d) || { echo "BLOCKER: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMPDIR_ROOT"' EXIT
AWK_STATUS="$TMPDIR_ROOT/awk-status"

# --- candidate file list: diff-modified tracked files + untracked files (C4) -------
# NUL-delimited listing (-z) read with mapfile -d '': git never C-quotes a path under -z,
# so a non-ASCII, control-character, or quote-bearing path comes back as its own bytes, and
# a newline inside a path stays one record instead of splitting into several unreadable
# short paths — the readability guard below sees exactly the files git named.
mapfile -d '' -t DIFF_FILES < <(git -C "$ROOT" diff --name-only -z "$BASE_REF" -- 2>/dev/null)
mapfile -d '' -t UNTRACKED_FILES < <(git -C "$ROOT" ls-files -z --others --exclude-standard)

# printf runs its format string once even with zero operands, so `"${DIFF_FILES[@]}"
# "${UNTRACKED_FILES[@]}"` both empty would still emit one NUL-terminated empty record — a
# clean tree with nothing to measure must produce zero candidates, not one invented path.
ALL_FILES=()
if [ "${#DIFF_FILES[@]}" -gt 0 ] || [ "${#UNTRACKED_FILES[@]}" -gt 0 ]; then
    mapfile -d '' -t ALL_FILES < <(printf '%s\0' "${DIFF_FILES[@]}" "${UNTRACKED_FILES[@]}" | sort -z -u)
fi

# Output buffers: verdict/skip/small lines first, then flag lines, then the summary —
# the order the sample block above shows.
LINES_BUF=""
FLAGS_BUF=""
N_FILES=0
N_WARN=0
N_BLOCK=0
N_SMALL=0
N_SKIP=0
N_FLAGS=0

for relpath in "${ALL_FILES[@]}"; do
    if [ ! -f "$ROOT/$relpath" ]; then
        # Most commonly a pure deletion; occasionally a path the NUL-delimited listing above
        # did not fully resolve. Reported rather than silently dropped, so it is
        # distinguishable from a clean run that measured nothing at all.
        N_FILES=$((N_FILES + 1))
        N_SKIP=$((N_SKIP + 1))
        LINES_BUF+="skip - - $relpath (path not readable)"$'\n'
        continue
    fi

    case "$relpath" in
        *.cc|*.cpp|*.h|*.hpp|*.go|*.rs|*.zig) family=clike ;;
        *.py|*.sh|*.bash) family=hashcmt ;;  # not "hash" — shellcheck SC2209 misreads that as the builtin
        *) family="" ;;
    esac

    N_FILES=$((N_FILES + 1))

    if [ -z "$family" ]; then
        N_SKIP=$((N_SKIP + 1))
        LINES_BUF+="skip - - $relpath (comment syntax unknown)"$'\n'
        continue
    fi

    ADDED_FILE="$TMPDIR_ROOT/added"
    is_untracked=0
    for u in "${UNTRACKED_FILES[@]}"; do
        [ "$u" = "$relpath" ] && { is_untracked=1; break; }
    done

    # Both branches below can fail without ADDED_FILE ever showing it: an untracked file's
    # line count can come back non-numeric (a broken interpreter prints nothing, `total_lines`
    # stays empty), and the hunk-parser pipeline's own awk stage can exit nonzero while still
    # leaving `> "$ADDED_FILE"` truncated-but-empty — indistinguishable, by content alone, from
    # a file that genuinely resolved zero added lines. Catching the failure here, before the
    # "no added lines resolved" test below, is what keeps that skip branch a data verdict
    # rather than an escape hatch for an interpreter that never ran.
    if [ "$is_untracked" = "1" ]; then
        total_lines=$("$AWK" 'END { print NR }' "$ROOT/$relpath")
        line_count_rc=$?
        if [ "$line_count_rc" -ne 0 ] || ! [[ "$total_lines" =~ ^[0-9]+$ ]]; then
            echo "failed: $relpath (line count)" >> "$AWK_STATUS"
            continue
        fi
        seq 1 "$total_lines" > "$ADDED_FILE" 2>/dev/null || : > "$ADDED_FILE"
    else
        git -C "$ROOT" diff "$BASE_REF" -- "$relpath" | "$AWK" "$HUNK_PARSER" > "$ADDED_FILE"
        hunk_rc="${PIPESTATUS[1]}"
        if [ "$hunk_rc" -ne 0 ]; then
            echo "failed: $relpath (hunk parser)" >> "$AWK_STATUS"
            continue
        fi
    fi

    # A file git listed as changed but whose hunk parser emitted no added-line-number at
    # all (a `.gitattributes` -diff path, binary detection) measured nothing — that is the
    # "ran clean, saw zero files" shape, not a genuinely small diff, so it must not fall
    # into the small-diff branch below and read as a measured verdict.
    if [ ! -s "$ADDED_FILE" ]; then
        N_SKIP=$((N_SKIP + 1))
        LINES_BUF+="skip - - $relpath (no added lines resolved)"$'\n'
        continue
    fi

    awk_rc=0
    RESULT=$("$AWK" -v FAMILY="$family" -v AF="$ADDED_FILE" -v MAXRUN="$MAX_COMMENT_RUN" "$CLASSIFIER" "$ADDED_FILE" "$ROOT/$relpath") || awk_rc=$?

    num=""; den=""
    while IFS=$'\t' read -r tag a b; do
        case "$tag" in
            NUM) num="$a"; den="$b" ;;
            FLAG)
                N_FLAGS=$((N_FLAGS + 1))
                FLAGS_BUF+=$(printf 'flag  %-18s %s:%s\n' "$a" "$relpath" "$b")
                FLAGS_BUF+=$'\n'
                ;;
        esac
    done <<< "$RESULT"

    # A classifier that fails outright, or one that runs to completion without ever
    # emitting its NUM record (a present-but-broken interpreter, a file it cannot
    # tokenise), must not fall through to num/den's empty defaults — that reads as a scan
    # that ran cleanly and measured nothing, rather than one that did not run at all.
    if [ "$awk_rc" -ne 0 ] || [ -z "$num" ] || [ -z "$den" ]; then
        echo "failed: $relpath" >> "$AWK_STATUS"
        continue
    fi

    if [ "$den" -lt "$MIN_ADDED_CODE" ]; then
        N_SMALL=$((N_SMALL + 1))
        LINES_BUF+="small - $num/$den $relpath (under MIN_ADDED_CODE)"$'\n'
        continue
    fi

    pct=$((num * 100 / den))
    if [ "$pct" -le "$WARN_THRESHOLD" ]; then
        verdict=PASS
    elif [ "$pct" -le "$BLOCK_THRESHOLD" ]; then
        verdict=WARN
        N_WARN=$((N_WARN + 1))
    else
        verdict=BLOCK
        N_BLOCK=$((N_BLOCK + 1))
    fi
    LINES_BUF+="$verdict $pct% $num/$den $relpath"$'\n'
done

if [ -s "$AWK_STATUS" ]; then
    echo "BLOCKER: $AWK failed on $(wc -l < "$AWK_STATUS") file(s) — result is not clean" >&2
    exit 1
fi

printf '%s' "$LINES_BUF"
printf '%s' "$FLAGS_BUF"
printf 'comment-gate: %d files · %d WARN · %d BLOCK · %d small · %d skipped · %d flags\n' \
    "$N_FILES" "$N_WARN" "$N_BLOCK" "$N_SMALL" "$N_SKIP" "$N_FLAGS"

exit 0
