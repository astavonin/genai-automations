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
# Boundary with tests/verify-workflow-safety.sh, which also compares config files: that suite
# owns the §4 status-marker gate end to end — its own gate model against the config, and every
# site restating that one rule — because its remaining sections depend on those values being
# right. This suite owns cross-file agreement for rules no suite models. A new declared-mirror
# set with no behavioural model behind it belongs here; another statement of the marker gate
# belongs in that suite's Section 0 site list.
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

GREP=/usr/bin/grep
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE="$ROOT/platforms/claude"
PAGETYPE="$CLAUDE/skills/workflows/page-type/SKILL.md"
APPENDIX_TEMPLATE="$CLAUDE/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md"

# The Command-files section near the end of this suite extracts Markdown sections through
# docgate's extract-section rather than carrying a second fence-aware parser here — one
# implementation needs no agreement test. A missing package would otherwise skip those
# assertions silently, which this repository treats as worse than no gate at all: fail the
# whole run now, loudly, rather than let the rest of the suite report a clean pass with
# part of it never checked.
if ! command -v extract-section >/dev/null 2>&1; then
    echo "FAIL: docgate is not installed — the 'extract-section' console script is not on PATH."
    echo "      Install it before running this suite: pip install -e $ROOT/tools/docgate"
    exit 1
fi

# fix-mr.md's shell-text assertions pipe extracted blocks to shellcheck — same reasoning as
# extract-section above: a missing tool must fail the whole run loudly, not silently skip part of it.
if ! command -v shellcheck >/dev/null 2>&1; then
    echo "FAIL: shellcheck is not installed — required by the fix-mr.md shell-text assertions."
    echo "      Install it before running this suite (e.g. apt install shellcheck)."
    exit 1
fi

# Bump when adding or removing an assertion. Asserted at the end so a block that silently
# skips itself shows up as a count mismatch instead of a green run — the sibling suite
# (verify-workflow-safety.sh) added this counter for the same reason; this suite had none,
# which is finding T3 in planning/genai-automations/appendix-page-type.
EXPECTED_TESTS=63

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
checked_refs=0
while IFS= read -r skill; do
    $GREP -qE '(See|see) `references/`|references/ directory' "$skill" || continue
    checked_refs=$((checked_refs + 1))
    refs="$(dirname "$skill")/references"
    [ -d "$refs" ] || { dangling="$dangling$skill → references/ (absent)\n"; continue; }
    [ -n "$(ls -A "$refs" 2>/dev/null)" ] || dangling="$dangling$skill → references/ (empty)\n"
done < <(find "$CLAUDE" -name 'SKILL.md')

# T3: this loop previously had no non-emptiness guard, unlike its two siblings in this file
# (checked -eq 0, n_src -eq 0 above/below) — if the body never runs, $dangling stays empty
# and the assertion passes vacuously, exactly like a skipped test reporting green.
if [ "$checked_refs" -eq 0 ]; then
    fail "every skill pointing at references/ has a non-empty one" "matched 0 SKILL.md files referencing references/ — the extraction is broken, not clean"
elif [ -z "$dangling" ]; then
    pass "every skill pointing at references/ has a non-empty one ($checked_refs checked)"
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

echo "== Change-class label sets agree across architecture, review-checklist, and testing tables =="

# M1 (code review main-2b1a277): the four class labels grade three independent tables. A class
# present in the architecture definition with no row in a grading table lets a reviewer improvise
# a severity, silently, for every finding in that review. Extraction is bound to each table's own
# first column (a line starting `| \`LABEL\` |`), not to any backtick mention of a label in
# surrounding prose, and bounded to each table's own section heading so a same-named label
# elsewhere in the file is never picked up.
#
# The guard's precondition: a class label is all-caps with hyphens (`[A-Z][A-Z-]*`). A label added in
# any other shape — lowercase, digits, an underscore — is invisible to the extractor and the sets
# still compare equal. Widening the character class is the wrong fix: it starts matching other
# backticked first columns inside the same heading-bounded range. Keep the convention instead.
#
# DESIGN-TEMPLATE.md's own header spelling (`**Class:** CI | TEST | ...`) is deliberately excluded
# — it is unbackticked and not a table row, so including it would false-red the one site that
# cannot use backticks.
class_labels() {   # $1: file  $2: heading line (fixed-string prefix match)
    awk -v h="$2" 'index($0,h)==1{f=1;next} f && /^#/{exit} f' "$1" \
        | $GREP -oE '^\| `[A-Z][A-Z-]*` \|' \
        | $GREP -oE '`[A-Z][A-Z-]*`' | sort -u
}

ARCH_CLASS="$CLAUDE/skills/domains/architecture/SKILL.md"
CHECKLIST_CLASS="$CLAUDE/skills/domains/quality-attributes/references/review-checklist.md"
TESTING_CLASS="$CLAUDE/skills/domains/testing/SKILL.md"

arch_class_labels=$(class_labels "$ARCH_CLASS" "## Change Class")
checklist_class_labels=$(class_labels "$CHECKLIST_CLASS" "## Change Class Calibration")
testing_class_labels=$(class_labels "$TESTING_CLASS" "### How many tests is the right number")

n_arch_class=$(printf '%s\n' "$arch_class_labels" | $GREP -c . || true)
if [ "$n_arch_class" -eq 0 ]; then
    fail "the four class labels are extracted from architecture/SKILL.md's Change Class table" "extraction found none"
elif [ "$arch_class_labels" = "$checklist_class_labels" ] && [ "$arch_class_labels" = "$testing_class_labels" ]; then
    pass "the class label set ($n_arch_class labels) agrees across architecture, review-checklist, and testing tables"
else
    fail "the class label set agrees across architecture, review-checklist, and testing tables" \
         "architecture=$(printf '%s' "$arch_class_labels" | tr '\n' ' ') checklist=$(printf '%s' "$checklist_class_labels" | tr '\n' ' ') testing=$(printf '%s' "$testing_class_labels" | tr '\n' ' ')"
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

# The no-phase-slot bullet is the classification's other inline enumeration. /review-spec is
# the newest member and the one with two ways to go wrong: named there with no command file
# behind it (a classification pointing at nothing), or promoted into the phase-command bullet,
# which asserts "these eight advance the workflow" and would then be counting nine.
CLAUDE_MD_ROSTER="$CLAUDE/CLAUDE.md"
noslot_line=$($GREP -m1 -F '**Workflow commands with no phase slot**' "$CLAUDE_MD_ROSTER")
phase_line=$($GREP -m1 -F '**Phase commands**' "$CLAUDE_MD_ROSTER")
bad=""
if [ -z "$noslot_line" ] || [ -z "$phase_line" ]; then
    bad="the command classification bullets were not found in CLAUDE.md"
else
    printf '%s' "$noslot_line" | $GREP -qF '`/review-spec`' \
        || bad="the no-phase-slot bullet does not name /review-spec; "
    printf '%s' "$phase_line" | $GREP -qF '`/review-spec`' \
        && bad="${bad}/review-spec appears in the eight-phase-command bullet; "
    [ -f "$CLAUDE/commands/review-spec.md" ] \
        || bad="${bad}commands/review-spec.md is absent; "
fi
if [ -z "$bad" ]; then
    pass "/review-spec is classified as a workflow command with no phase slot and its command file exists"
else
    fail "/review-spec is classified as a workflow command with no phase slot and its command file exists" "$bad"
fi

echo "== Book page-type activation token =="

# T2(a): write.md and writer.md each declare the [MODE: book-article/*] activation token
# independently — a mirror with no behavioural model behind it. Require the sets to agree
# and the superseded bare form (no page-type suffix) to be gone from both.
write_modes=$($GREP -oE '\[MODE: book-article/[a-z]+\]' "$CLAUDE/commands/write.md" | sort -u)
writer_modes=$($GREP -oE '\[MODE: book-article/[a-z]+\]' "$CLAUDE/agents/writer.md" | sort -u)
n_write_modes=$(printf '%s\n' "$write_modes" | $GREP -c . || true)
if [ "$n_write_modes" -eq 0 ]; then
    fail "activation-token set extracted from write.md" "extraction found none"
elif [ "$write_modes" = "$writer_modes" ]; then
    pass "activation-token set ($n_write_modes forms) agrees between write.md and writer.md"
else
    fail "activation-token set agrees between write.md and writer.md" \
         "$(diff <(printf '%s\n' "$write_modes") <(printf '%s\n' "$writer_modes"))"
fi

bare_hits=$( { $GREP -F '[MODE: book-article]' "$CLAUDE/commands/write.md" "$CLAUDE/agents/writer.md" || true; } | wc -l)
if [ "$bare_hits" -eq 0 ]; then
    pass "the superseded bare [MODE: book-article] token (no page-type suffix) is gone from both"
else
    fail "the superseded bare [MODE: book-article] token (no page-type suffix) is gone from both" "$bare_hits occurrence(s) remain"
fi

echo "== Appendix path-form agreement =="

# T2(b) / M5: page-type/SKILL.md's Resolution table is the single source for the appendix
# issue-folder shape (`A<N>-<slug>`, not a bare glob). A site that spells out the loose form
# silently accepts a folder the fragment itself says must be rejected.
#
# Two hardcodes made this fragile. (1) matching the row by its label text ("Issue folder")
# false-reds on a benign label rename — extract the first data row after the table's header
# separator instead, which is structural, not textual. (2) extracting the appendix cell by
# backtick field POSITION (awk -F'`' '{print $4}') silently shifts to the wrong field when an
# unrelated backtick-quoted token is added anywhere earlier in the row — extract by content
# instead: the backtick-quoted segment that contains "appendix/issues/", wherever it sits.
res_row=$(awk '
  /^## Resolution/ { f=1 }
  f && /^\|---/ { sep=1; next }
  f && sep && /^\|/ { print; exit }
' "$PAGETYPE")
appendix_form=$(printf '%s' "$res_row" | $GREP -oE '`[^`]*appendix/issues/[^`]*`' | tr -d '`')
if [ -z "$appendix_form" ]; then
    fail "appendix issue-folder form extracted from the Resolution table" "row='$res_row'"
else
    # The glob character is what makes a form "loose", not a trailing slash after it — a
    # trailing-slash requirement here lets `appendix/issues/*` (no slash) through unnoticed.
    loose_hits=$($GREP -rn 'appendix/issues/\*' --include='*.md' "$CLAUDE" || true)
    if [ -z "$loose_hits" ]; then
        pass "the loose appendix form (appendix/issues/*, no A<N> identifier) appears nowhere"
    else
        fail "the loose appendix form (appendix/issues/*, no A<N> identifier) appears nowhere" "$loose_hits"
    fi

    bad_sites=""
    n_sites=0
    while IFS= read -r file; do
        n_sites=$((n_sites + 1))
        $GREP -qF "$appendix_form" "$file" || bad_sites="$bad_sites${file#"$ROOT"/} (spells out an appendix path but not the canonical form)\n"
    done < <($GREP -rl 'appendix/issues/' --include='*.md' "$CLAUDE")
    if [ "$n_sites" -eq 0 ]; then
        fail "every site spelling out the appendix path uses the canonical form" "no site spells the path out at all — extraction broken"
    elif [ -z "$bad_sites" ]; then
        pass "every site spelling out the appendix path ($n_sites of them) uses the canonical form"
    else
        fail "every site spelling out the appendix path uses the canonical form" "$(printf "%b" "$bad_sites")"
    fi
fi

echo "== Rejection-block deferral =="

# T2(c) / M4: only the three commands that independently resolve and reject a page-type
# path (spec, write, review-article) can hit the rejection branch — review-article-fix-loop
# delegates entirely to /review-article, and the non-command consumers never resolve a path
# at all, so scoping this to "every Consumers-table row" would force an artificial reference
# into files with nothing to defer to.
#
# Accepting EITHER the block's first line OR the phrase "fragment's error text" means a
# consumer that RESTATES the block verbatim also satisfies the check, since restating
# includes the first line — the opposite of deferring to it. It also cannot tell a genuine
# deferral from a surviving sentence that names the phrase while mandating the forbidden
# fallback behaviour ("...today, guess the closest page type and continue"). Extracting
# block_first_line from PAGETYPE itself, rather than hardcoding the sentence, also keeps the
# check from false-redding on a benign reword of that line.
block_first_line=$(awk '
  /\*\*Rejection is mandatory\.\*\*/ { f=1 }
  f && /^```/ { fence++; if (fence == 1) next; else exit }
  f && fence == 1 { print; exit }
' "$PAGETYPE")
if [ -z "$block_first_line" ]; then
    fail "rejection block first line found in page-type/SKILL.md" "extraction found none"
else
    bad=""
    for rel in commands/spec.md commands/write.md commands/review-article.md; do
        f="$CLAUDE/$rel"
        if $GREP -qF "$block_first_line" "$f"; then
            bad="$bad$rel (restates the rejection block verbatim instead of deferring)\n"
        elif ! $GREP -qF "fragment's error text" "$f"; then
            bad="$bad$rel (no deferral phrase found)\n"
        elif $GREP -qiE 'guess[^.]*page type' "$f"; then
            bad="$bad$rel (deferral phrase present but a guess-and-continue sentence survives)\n"
        fi
    done
    if [ -z "$bad" ]; then
        pass "every path-resolving command defers to the fragment's rejection text without restating or bypassing it"
    else
        fail "every path-resolving command defers to the fragment's rejection text without restating or bypassing it" "$(printf "%b" "$bad")"
    fi
fi

echo "== Source Requirement (SR) set agreement =="

# T2(d) / M2: commands/spec.md's "Section rules to enforce — appendix" bullet is a summary
# of APPENDIX-SPEC-TEMPLATE.md §3; an omitted SR silently changes what a spec is graded on
# without changing what SCOPES.md Scope 2A checks it against.
#
# Bounded on `## 3\.` (the number only) rather than `## 3\. Source Requirements` (the
# number plus its current title) — a benign heading reword would otherwise false-red this
# extraction even though every SR line inside the section is untouched.
tmpl_sr=$(awk '/^## 3\./{f=1;next} /^## 4\./{f=0} f' "$APPENDIX_TEMPLATE" \
    | $GREP -oE 'SR[0-9]+' | sort -u)
spec_sr=$($GREP -oE 'SR[0-9]+' "$CLAUDE/commands/spec.md" | sort -u)
n_tmpl=$(printf '%s\n' "$tmpl_sr" | $GREP -c . || true)
if [ "$n_tmpl" -eq 0 ]; then
    fail "SR set extracted from APPENDIX-SPEC-TEMPLATE.md §3" "extraction found none"
elif [ "$tmpl_sr" = "$spec_sr" ]; then
    pass "SR set ($n_tmpl rules) agrees between APPENDIX-SPEC-TEMPLATE.md §3 and commands/spec.md"
else
    fail "SR set agrees between APPENDIX-SPEC-TEMPLATE.md §3 and commands/spec.md" \
         "$(diff <(printf '%s\n' "$tmpl_sr") <(printf '%s\n' "$spec_sr"))"
fi

echo "== SP-9 section lists agree with the templates they name =="

# Both SP-9 criteria in commands/review-spec.md hardcode their template's §1-§5 section list.
# The block cannot point at the template instead — it is pasted whole into reviewer and Step G
# verifier prompts, which hold no other document — so this is a real mirror, and SP-9 is the
# only blocker-severity criterion in the command: a retitled or renumbered template section
# silently changes what a spec review blocks on, in the one criterion that can stop an approval.
#
# Both sides extract by content, neither by position. Template side: its own `## N. Title`
# headings. Command side: the first contiguous comma-separated `§N Title` run starting at §1,
# which is immune to a reword of the lead-in ("The sections ... requires are present:") and
# stops at the sentence's period — a lead-in-anchored match instead swallows the later
# "a spec with no §2 has no claims" into the list. The pair is selected by the `planning/<name>`
# path on the criterion line, not by order: `SPEC-TEMPLATE.md` is a suffix of
# `APPENDIX-SPEC-TEMPLATE.md`, so a bare basename match returns the appendix line for both.
REVIEW_SPEC="$CLAUDE/commands/review-spec.md"
sp9_word='[A-Za-z][A-Za-z-]*( [A-Z][A-Za-z-]*)*'
sp9_run="§1 $sp9_word(, §[2-5] $sp9_word)*"
bad=""
n_sp9=0
for tmpl in APPENDIX-SPEC-TEMPLATE.md SPEC-TEMPLATE.md; do
    n_sp9=$((n_sp9 + 1))
    tmpl_sections=$($GREP -oE '^## [1-5]\. .+' "$CLAUDE/skills/workflows/planning/$tmpl" \
        | sed -E 's/^## ([1-5])\. /§\1 /' | sort)
    sp9_line=$($GREP -m1 -E "SP-9 —.*planning/$tmpl" "$REVIEW_SPEC")
    crit_sections=$(printf '%s' "$sp9_line" | $GREP -oE "$sp9_run" | head -1 \
        | tr ',' '\n' | sed 's/^ //' | sort)
    n_tmpl_sec=$(printf '%s\n' "$tmpl_sections" | $GREP -c . || true)
    n_crit_sec=$(printf '%s\n' "$crit_sections" | $GREP -c . || true)
    if [ -z "$sp9_line" ]; then
        bad="$bad$tmpl: no SP-9 criterion line names it; "
    elif [ "$n_tmpl_sec" -eq 0 ]; then
        bad="$bad$tmpl: no '## N. Title' headings extracted from the template; "
    elif [ "$n_crit_sec" -eq 0 ]; then
        bad="$bad$tmpl: no section run extracted from its SP-9 criterion; "
    elif [ "$tmpl_sections" != "$crit_sections" ]; then
        bad="$bad$tmpl: $(diff <(printf '%s\n' "$tmpl_sections") <(printf '%s\n' "$crit_sections") \
            | sed 's/^</only in template: /; s/^>/only in SP-9: /' | tr '\n' ' '); "
    fi
done
if [ -z "$bad" ]; then
    pass "both SP-9 section lists ($n_sp9 criteria) equal the §1-§5 headings of the template each names"
else
    fail "both SP-9 section lists equal the §1-§5 headings of the template each names" "$bad"
fi

echo "== the Approved-writer rule survives where APPENDIX-SPEC-TEMPLATE.md points =="

# APPENDIX-SPEC-TEMPLATE.md's ## Rules does not restate the Draft/Approved rule — it points
# at SPEC-TEMPLATE.md's ## Rules for it. That pointer is a backticked prose path, not a
# `Read ~/.claude/<path>` directive, so the Read-pointer loop above does not cover it:
# deleting the target entry leaves the appendix template pointing at a section that is gone
# and takes /review-spec's sole-writer contract with it, in both templates at once.
# Anchor on the entry's own claim, not on a heading or a bare basename — SPEC-TEMPLATE.md is
# a suffix of APPENDIX-SPEC-TEMPLATE.md, and the appendix file names both paths.
approved_rule='`/review-spec` is the only writer of `Approved`'
bad=""
spec_rules=$(awk '/^## Rules/{f=1;next} f && /^## /{f=0} f' \
    "$CLAUDE/skills/workflows/planning/SPEC-TEMPLATE.md")
printf '%s' "$spec_rules" | $GREP -qF "$approved_rule" \
    || bad="SPEC-TEMPLATE.md ## Rules no longer states the sole-writer rule; "
appendix_rule=$($GREP -m1 -F "$approved_rule" \
    "$CLAUDE/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md")
if [ -z "$appendix_rule" ]; then
    bad="${bad}APPENDIX-SPEC-TEMPLATE.md no longer carries the rule entry; "
else
    printf '%s' "$appendix_rule" | $GREP -qF 'planning/SPEC-TEMPLATE.md' \
        || bad="${bad}APPENDIX-SPEC-TEMPLATE.md's rule entry no longer points at SPEC-TEMPLATE.md; "
fi
if [ -z "$bad" ]; then
    pass "SPEC-TEMPLATE.md ## Rules holds the Approved-writer rule the appendix template points at"
else
    fail "SPEC-TEMPLATE.md ## Rules holds the Approved-writer rule the appendix template points at" "$bad"
fi

echo "== page-type/SKILL.md Consumers-table completeness =="

# T2(e) / M3: the Consumers table is a manually maintained index; it must equal the
# discovered referrer set exactly, or a new consumer joins silently and the table
# under-reports again on day one, which is how this drift started.
table_paths=$($GREP -oE '^\| `~/\.claude/[^`]+`' "$PAGETYPE" | sed -E 's#^\| `~/\.claude/##' | sed -E 's/`$//' | sort -u)
n_table=$(printf '%s\n' "$table_paths" | $GREP -c . || true)
discovered=$($GREP -rl -F 'page-type/SKILL.md' --include='*.md' "$CLAUDE" \
    | sed "s#^$CLAUDE/##" | $GREP -v -F 'skills/workflows/page-type/SKILL.md' | sort -u)
if [ "$n_table" -eq 0 ]; then
    fail "Consumers table rows extracted from page-type/SKILL.md" "extraction found none"
elif [ "$table_paths" = "$discovered" ]; then
    pass "Consumers table ($n_table rows) equals the discovered referrer set"
else
    fail "Consumers table equals the discovered referrer set" \
         "$(diff <(printf '%s\n' "$table_paths") <(printf '%s\n' "$discovered") | sed 's/^</  only in table: /; s/^>/  only on disk: /')"
fi

echo "== Article-review commands avoid hardcoded milestone-form issue-folder paths =="

# A literal milestone-form path spelled out in review-article.md or review-article-fix-loop.md
# and then passed as a parameter VALUE to another skill (e.g. status-marker-verify's
# `review_file`) is functionally wrong for an appendix page, not just a readability shortcut —
# the receiving skill has no way to know either command's internal path convention. Check both
# files against the general pattern — any `milestone-XX` segment immediately followed by
# `/issues/<NNN-name>`, book-prefixed or not — rather than one exact historical literal:
# copying a sibling loop's own milestone-form report path (`planning/<goal>/milestone-XX/
# issues/<NNN-name>/...`) is a realistic regression a single fixed literal does not catch,
# since that form has no `book/` segment and different brackets around `<name>`.
FIXLOOP="$CLAUDE/commands/review-article-fix-loop.md"
REVIEWARTICLE="$CLAUDE/commands/review-article.md"
bad=""
for f in "$FIXLOOP" "$REVIEWARTICLE"; do
    [ -f "$f" ] || { bad="$bad$f (file absent)\n"; continue; }
    n=$($GREP -cE 'milestone-XX[^/]*/issues/<NNN-name>' "$f" || true)
    [ "$n" -gt 0 ] && bad="$bad${f#"$ROOT"/}: $n hardcoded occurrence(s)\n"
done
if [ -z "$bad" ]; then
    pass "neither review-article.md nor review-article-fix-loop.md hardcodes a milestone-form issue-folder path — both use <issue-folder>"
else
    fail "neither review-article.md nor review-article-fix-loop.md hardcodes a milestone-form issue-folder path" "$(printf "%b" "$bad")"
fi

# FIXLOOP's annotation-coherence check must still exempt an appendix draft from the
# permalink/commit-hash instruction (its evidence blocks are not GitHub-permalinked source,
# so the check would otherwise ask the writer to fabricate a commit hash). Matching the exact
# phrase "Appendix pages: skip this check" false-reds on a benign reword ("bypass" for "skip",
# etc.) even though the behaviour is unchanged — check the structural relationship instead:
# the paragraph opening on "Appendix pages" mentions skipping within a few lines.
#
# H3: that loose window+keyword check is itself defeatable — a decoy lead-in
# "**Appendix pages: do not skip this check**" contains "Appendix pages" and "skip" and
# satisfies the old check even though it states the opposite of an exemption. Anchor on the
# bold lead-in line itself and require the skip-word to appear with no intervening
# negation ("do not" / "don't" / "never") ahead of it on that line.
if [ -f "$FIXLOOP" ]; then
    appendix_line=$($GREP -m1 -E '\*\*Appendix pages:' "$FIXLOOP")
    APOS="'"
    neg_pattern="(do not|don${APOS}t|never)[^.]*(skip|bypass|exempt|omit)"
    if [ -z "$appendix_line" ]; then
        fail "the annotation-coherence check exempts appendix drafts from the permalink/commit-hash instruction" \
             "no '**Appendix pages:' lead-in line found — an appendix draft's evidence blocks would be asked to fabricate a commit hash"
    elif printf '%s' "$appendix_line" | $GREP -qiE 'skip|bypass|exempt|omit' \
         && ! printf '%s' "$appendix_line" | $GREP -qiE "$neg_pattern"; then
        pass "the annotation-coherence check exempts appendix drafts from the permalink/commit-hash instruction"
    else
        fail "the annotation-coherence check exempts appendix drafts from the permalink/commit-hash instruction" \
             "line: $appendix_line"
    fi
fi

echo "== Appendix TODO match rule: single statement =="

# T1 ledger entry 1 (the A-page TODO rule drift): TODOS.md's header claims it "owns the TODO
# extraction rules and is authoritative for them," but page-type/SKILL.md restated the exact
# appendix match rule (the A2-vs-A20 whole-token-boundary example) despite its own text
# claiming to state only the identifier mapping.
#
# A bare `grep -rl 'A20'` file-level match has two failure modes — (1) gutting the operative
# clause while some unrelated prose mention of "A20" survives in the owner file still passes
# green, since the file itself still matches; (2) an unrelated `0xA20` token anywhere in the
# corpus turns it red. Anchor on the operative clause's structural content — the
# backtick-quoted `A2`/`A20` pair on the same line — which is immune to both: deleting the
# clause drops the pair entirely (extraction goes to zero, correctly caught below), and
# `0xA20` is not backtick-quoted as `A20` paired with a backtick-quoted `A2` on that line.
owner="skills/workflows/article-review/TODOS.md"
op_pattern='`A2`.*`A20`'
sites=$($GREP -rlE "$op_pattern" --include='*.md' "$CLAUDE" | sed "s#^$CLAUDE/##" | sort -u)
n_sites=$(printf '%s\n' "$sites" | $GREP -c . || true)
if [ "$n_sites" -eq 0 ]; then
    fail "the appendix TODO match rule's operative clause is stated somewhere" "extraction found no \`A2\`...\`A20\` pair — the rule text may have changed or been deleted"
elif [ "$n_sites" -eq 1 ] && [ "$sites" = "$owner" ]; then
    pass "the appendix TODO match rule has exactly one statement ($owner)"
else
    fail "the appendix TODO match rule has exactly one statement ($owner)" "found in: $sites"
fi

echo "== TODOS.md consumers name the appendix branch =="

# The assertion above only catches the rule losing its single statement. It does not catch
# commands/review-article.md's 2b reverting to an unbranched form that never mentions the
# appendix page type — the Consumers-table check is satisfied by any reference to
# page-type/SKILL.md anywhere in the file, which the Setup section's unrelated read call
# already provides regardless of what 2b itself says. Check that each of the three commands
# reading TODOS.md names both "step 0a" and "appendix" within the paragraph that follows the
# read call — text an unbranched revert would drop.
missing=""
n_consumers=0
for rel in commands/spec.md commands/write.md commands/review-article.md; do
    f="$CLAUDE/$rel"
    n_consumers=$((n_consumers + 1))
    window=$($GREP -A8 -F 'article-review/TODOS.md' "$f")
    if printf '%s' "$window" | $GREP -qi 'step 0a' && printf '%s' "$window" | $GREP -qi 'appendix'; then
        :
    else
        missing="$missing$rel\n"
    fi
done
if [ "$n_consumers" -eq 0 ]; then
    fail "every command reading TODOS.md names step 0a and appendix in its TODO-scan step" "extraction found no consumers — broken"
elif [ -z "$missing" ]; then
    pass "all $n_consumers command(s) reading TODOS.md name step 0a and appendix in their TODO-scan step"
else
    fail "every command reading TODOS.md names step 0a and appendix in its TODO-scan step" "$(printf "%b" "$missing")"
fi

echo "== Unverified-claim marker: four mandated hops survive verbatim =="

# The [UNVERIFIED:] marker is the direct mitigation for a claim sourced from analysis.md —
# see observed-failures.md entry 2. It only works if the token survives every hop verbatim.
# Anchored to each hop's actual definition text, not a bare "[UNVERIFIED:" substring — a
# prose mention of the token (e.g. inside another hop's own explanatory aside) would
# otherwise satisfy a looser check without the definition itself surviving.
#
# Hop 4's anchor text — "claim marked `[UNVERIFIED: ...]` or `[VERIFY: ...]`" — occurs TWICE
# in SCOPES.md: at Scope 2A criterion 2 itself, and again in the Codex Requirements bullet
# "Unverified claims hedged (2A.2, appendix only)". Either satisfies a whole-file `grep -qF`,
# so deleting criterion 2 outright while the Codex bullet survives would still pass. Anchor
# hop 4 on criterion 2's own numbering instead — the line matching `^2\. \*\*Every claim
# marked` — so only that specific criterion, not any occurrence of the phrase, is checked.
missing_hop=""
$GREP -qF '`[UNVERIFIED: <what is missing>]`' "$CLAUDE/skills/workflows/page-type/SKILL.md" \
    || missing_hop="${missing_hop}skills/workflows/page-type/SKILL.md (marker table)\n"
$GREP -qF '[UNVERIFIED: no device access]' "$CLAUDE/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md" \
    || missing_hop="${missing_hop}skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md (§2 example row)\n"
$GREP -qF '[UNVERIFIED: <what is missing>]' "$CLAUDE/skills/workflows/planning/BRIEF-TEMPLATE.md" \
    || missing_hop="${missing_hop}skills/workflows/planning/BRIEF-TEMPLATE.md (§9 bullet)\n"
criterion2=$($GREP -m1 -E '^2\. \*\*Every claim marked' "$CLAUDE/skills/workflows/article-review/SCOPES.md")
if [ -z "$criterion2" ]; then
    missing_hop="${missing_hop}skills/workflows/article-review/SCOPES.md (Scope 2A criterion 2 — no line starting '2. **Every claim marked')\n"
else
    printf '%s' "$criterion2" | $GREP -qF '[UNVERIFIED: ...]' \
        && printf '%s' "$criterion2" | $GREP -qF '[VERIFY: ...]' \
        || missing_hop="${missing_hop}skills/workflows/article-review/SCOPES.md (Scope 2A criterion 2 — missing one of the two marker tokens)\n"
fi
if [ -z "$missing_hop" ]; then
    pass "the [UNVERIFIED:] marker's definition is stated at all 4 mandated hops"
else
    fail "the [UNVERIFIED:] marker's definition is stated at all 4 mandated hops" "missing from:\n$(printf "%b" "$missing_hop")"
fi

# H3: a whole-file `grep -qF '§9 only'` is satisfied by a decoy sentence anywhere in the
# file — inverting the Routing (appendix) paragraph itself to "§7.5 and §8" while a decoy
# "§9 only" sentence survives elsewhere left the old check green. Anchor on the paragraph's
# own lead-in instead, so only that specific paragraph's content is checked.
routing_line=$($GREP -m1 -F '**Routing (appendix).**' "$CLAUDE/commands/write.md")
if [ -z "$routing_line" ]; then
    fail "write.md 2d's Routing (appendix) paragraph names §9 as the sole destination for unverified rows" \
         "the '**Routing (appendix).**' paragraph is absent — an unverified claim could silently reach a verified-fact section"
elif printf '%s' "$routing_line" | $GREP -qF '§9 only' && ! printf '%s' "$routing_line" | $GREP -qF '§7.5 and §8'; then
    pass "write.md 2d's Routing (appendix) paragraph names §9 as the sole destination for unverified rows"
else
    fail "write.md 2d's Routing (appendix) paragraph names §9 as the sole destination for unverified rows" \
         "paragraph: $routing_line"
fi

echo "== review-planning-update: no dangling optional-parameter mechanism =="

# A documented-but-unpassed optional parameter made an appendix review silently derive a
# milestone status.md that "writes to nothing" — the fix removes the parameter rather than
# propagating it to every call site: the fragment's Step 1/2 skip condition is now derived
# structurally from the issue-folder path (no milestone-XX segment), so there is nothing to
# pass and nothing to keep in sync. Guard the deletion: no "Caller may specify"
# optional-parameter mechanism should reappear in the shared-fragment corpus, and the removed
# parameter name must not reappear anywhere.
bad=""
opt_hits=$($GREP -rl 'Caller [Mm]ay [Ss]pecify' --include='*.md' "$CLAUDE/skills" || true)
[ -n "$opt_hits" ] && bad="${bad}Caller-may-specify mechanism reintroduced in: $opt_hits\n"
status_file_hits=$($GREP -rl 'status_file' --include='*.md' "$CLAUDE" || true)
[ -n "$status_file_hits" ] && bad="${bad}status_file reappeared in: $status_file_hits\n"
if [ -z "$bad" ]; then
    pass "no optional-parameter mechanism or status_file has reappeared"
else
    fail "no optional-parameter mechanism or status_file has reappeared" "$(printf "%b" "$bad")"
fi

echo "== page-type vocabulary implies a pointer to the fragment =="

# The Consumers-table check above can only see a file that ALREADY names page-type/SKILL.md
# — it is blind to a file that carries appendix-page-type behaviour without naming the
# fragment at all (review-planning-update/SKILL.md once carried appendix rules with zero
# references, invisible to that discovery method). Add the converse: every file using
# page-type vocabulary (the appendix path shape or its identifier placeholder) must point
# back to the fragment somewhere.
vocab_hits=$($GREP -rl -E 'appendix/issues/|A<N>-<slug>' --include='*.md' "$CLAUDE" \
    | sed "s#^$CLAUDE/##" | $GREP -v -F 'skills/workflows/page-type/SKILL.md' | sort -u)
n_vocab=$(printf '%s\n' "$vocab_hits" | $GREP -c . || true)
missing=""
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    $GREP -qF 'page-type/SKILL.md' "$CLAUDE/$rel" || missing="$missing$rel\n"
done <<EOF
$vocab_hits
EOF
if [ "$n_vocab" -eq 0 ]; then
    fail "every file carrying page-type vocabulary points back to page-type/SKILL.md" "extraction found no files carrying appendix vocabulary — broken"
elif [ -z "$missing" ]; then
    pass "all $n_vocab file(s) carrying page-type vocabulary point back to page-type/SKILL.md"
else
    fail "every file carrying page-type vocabulary points back to page-type/SKILL.md" "$(printf "%b" "$missing")"
fi

echo "== A-pages never cite code: no conditional carve-out remains =="

# page-type/SKILL.md states unconditionally that an A-page never cites code. A conditional
# carve-out ("...or appendix if the draft cites code" / "If the draft does cite code...")
# reopens the path this rule exists to close — guard against its reintroduction the same way
# the bare-MODE-token check above guards its own deletion.
carveout_hits=$($GREP -rniE 'or appendix if the draft cites code|if the draft does cite code' --include='*.md' "$CLAUDE" || true)
if [ -z "$carveout_hits" ]; then
    pass "no 'appendix ... cites code' conditional carve-out remains in the corpus"
else
    fail "no 'appendix ... cites code' conditional carve-out remains in the corpus" "$carveout_hits"
fi

# Round-3 stall diagnosis: every assertion added that round guarded a deletion staying
# deleted (status_file, the carve-out phrases, the bare MODE token) — none guarded a
# newly-added rule's presence, which is how inverting the rule at its source (H1, H2 in
# planning/genai-automations/appendix-page-type/code-review.md) left the whole suite green.
# The five blocks below close that gap for the six round-3 rules the report identifies as
# unguarded, anchored on each rule's own operative content rather than on the absence of
# its predecessor.

echo "== review-planning-update Steps 1-2: skip condition tests issue_folder against the appendix form =="

# H2: the predicate this replaces had no explicit input and, read structurally, was
# satisfied by every flat non-milestone planning/ folder in this repo. The fix takes the
# resolved issue-folder path as an explicit `issue_folder` parameter and tests it against
# the appendix form specifically. Anchor on the "**Skip condition.**" line itself (this
# fragment's paragraphs are unwrapped, one per line) so a revert to the old generic wording
# — which has neither `issue_folder` nor the appendix form on that line — is caught.
RPU="$CLAUDE/skills/workflows/review-planning-update/SKILL.md"
skip_line=$($GREP -m1 -F '**Skip condition.**' "$RPU")
bad=""
if [ -z "$skip_line" ]; then
    bad="no '**Skip condition.**' line found in Step 1"
else
    printf '%s' "$skip_line" | $GREP -qF 'issue_folder' || bad="${bad}skip condition does not test issue_folder; "
    printf '%s' "$skip_line" | $GREP -qF 'appendix/issues/A<N>-<slug>' || bad="${bad}skip condition does not name the appendix issue-folder form; "
fi
$GREP -qF 'Applies only to a page type with a milestone folder' "$RPU" \
    && bad="${bad}the old no-input predicate sentence has reappeared; "
if [ -z "$bad" ]; then
    pass "Steps 1-2 skip condition tests the explicit issue_folder parameter against the appendix issue-folder form"
else
    fail "Steps 1-2 skip condition tests the explicit issue_folder parameter against the appendix issue-folder form" "$bad"
fi

echo "== A-pages never cite code: the rule itself is present and unconditional =="

# H1: every deletion the appendix simplification made (carve-outs, Scope 1 suppression,
# the fix-loop annotation exemption) is downstream of this one sentence. The carve-out
# guard above only catches a *reintroduced* carve-out phrase — it cannot notice this
# sentence itself being softened or deleted. Anchor on the exact bolded sentence and
# reject any conditional token on it.
rule_line=$($GREP -m1 -F '**An appendix page never cites code.**' "$PAGETYPE")
if [ -z "$rule_line" ]; then
    fail "the 'An appendix page never cites code' rule is present in page-type/SKILL.md → Resolution" \
         "the bolded sentence is absent — extraction found no exact match"
elif printf '%s' "$rule_line" | $GREP -qiE '\b(if|unless|except|when)\b'; then
    fail "the 'An appendix page never cites code' rule is present in page-type/SKILL.md → Resolution" \
         "the sentence carries a conditional token: $rule_line"
else
    pass "the 'An appendix page never cites code' rule is present in page-type/SKILL.md → Resolution and carries no conditional token"
fi

echo "== writer.md Book Article Mode: the [MODE: book-article/appendix] paragraph keeps its operative clauses =="

# T1: a prior mutation replaced this entire branch with a bare pointer to
# page-type/SKILL.md and every existing assertion stayed green, because the only existing
# check (Book page-type activation token, above) tests the token SET, not this paragraph's
# content. Anchor on the paragraph's own lead-in and require its load-bearing sentinels to
# survive on that line.
mode_line=$($GREP -m1 -F '`[MODE: book-article/appendix]` — a reference appendix page.' "$CLAUDE/agents/writer.md")
bad=""
if [ -z "$mode_line" ]; then
    bad="the mode paragraph itself is absent"
else
    printf '%s' "$mode_line" | $GREP -qF '(none — fact contract)' || bad="${bad}(none — fact contract) clause missing; "
    printf '%s' "$mode_line" | $GREP -qF 'n/a — appendix page' || bad="${bad}n/a — appendix page clause missing; "
    printf '%s' "$mode_line" | $GREP -qF 'do not invent a commit hash' || bad="${bad}do-not-invent-a-commit-hash clause missing; "
    printf '%s' "$mode_line" | $GREP -qF '§9 only' || bad="${bad}§9-only routing clause missing; "
fi
if [ -z "$bad" ]; then
    pass "the [MODE: book-article/appendix] paragraph retains its operative clauses (fact-contract sentinels, no-commit-hash, §9-only routing)"
else
    fail "the [MODE: book-article/appendix] paragraph retains its operative clauses" "$bad"
fi

echo "== write.md step 4: the appendix-additional-pass bullet list is intact =="

# T1: "a rule stated only here does not reach [the agent]" is the bullet list's own stated
# failure mode. Window-bounded between the heading and the next mode's heading so deleting
# the whole block (not just individual bullets) is caught too.
window=$(awk '
  /\*\*Appendix page — additionally pass\*\*/ { f=1 }
  f && /\*\*Non-book mode:\*\*/ { exit }
  f { print }
' "$CLAUDE/commands/write.md")
bad=""
if [ -z "$window" ]; then
    bad="the 'Appendix page — additionally pass' heading is absent"
else
    printf '%s' "$window" | $GREP -qF 'analysis.md' || bad="${bad}analysis.md bullet missing; "
    printf '%s' "$window" | $GREP -qF '2d routing rule verbatim' || bad="${bad}2d-routing-rule bullet missing; "
    printf '%s' "$window" | $GREP -qF 'n/a — appendix page' || bad="${bad}companion-metadata bullet missing; "
    printf '%s' "$window" | $GREP -qF '(none — fact contract)' || bad="${bad}§7.1-§7.4 sentinel bullet missing; "
fi
if [ -z "$bad" ]; then
    pass "write.md step 4 retains all 4 appendix-additional-pass bullets"
else
    fail "write.md step 4 retains all 4 appendix-additional-pass bullets" "$bad"
fi

echo "== review-article.md Step 2: Agent 1's appendix Scope-1 suppression and Scope 2A reassignment are intact =="

# T1: a plain revert of Agent 1's launch bullet to the unbranched main-only form stayed
# green under the old suite, and round 3 separately left Agent 1 launched with nothing to
# do for an appendix page (H6, fixed by reassigning it Scope 2A) — this assertion guards
# both the suppression clause and its replacement on the same anchored line.
agent1_line=$($GREP -m1 -F '**Agent 1**' "$CLAUDE/commands/review-article.md")
bad=""
if [ -z "$agent1_line" ]; then
    bad="no '**Agent 1**' launch line found in Step 2"
else
    printf '%s' "$agent1_line" | $GREP -qiF 'appendix' || bad="${bad}no appendix branch in the Agent 1 launch line; "
    printf '%s' "$agent1_line" | $GREP -qF 'Scope 1 is suppressed entirely' || bad="${bad}the Scope-1 suppression instruction is gone; "
    printf '%s' "$agent1_line" | $GREP -qF 'Scope 2A' || bad="${bad}Agent 1 is no longer reassigned Scope 2A; "
fi
if [ -z "$bad" ]; then
    pass "review-article.md Step 2 keeps Agent 1's appendix Scope-1 suppression and Scope 2A reassignment"
else
    fail "review-article.md Step 2 keeps Agent 1's appendix Scope-1 suppression and Scope 2A reassignment" "$bad"
fi

echo "== Scope 2A criteria, Codex bullets, and label-mapping rows agree =="

# This mirror is load-bearing and cannot be collapsed into a single pointer — codex-flow
# review runs with --ignore-user-config --ignore-rules and reads only its bundled resources
# plus the request document, so the Codex-facing bullets cannot just say "see SCOPES.md";
# the criteria text must be copied into the request verbatim. A dropped bullet or a severity
# that disagrees between the criteria and the Codex-facing copy means Claude and Codex grade
# an appendix draft against different rules inside the same review.
SCOPES="$CLAUDE/skills/workflows/article-review/SCOPES.md"
# Criteria severities: bound extraction to the Scope 2A section only — its numbered
# criteria share the "N. **...**" shape with every other scope's numbered list, so an
# unbounded extraction silently grabs the wrong scope's items instead of failing loudly.
#
# Criteria 3 and 4 moved to /review-spec, so the surviving numbers are 1, 2 and 5 — a gap,
# not a range. The two extraction regexes (`^[1-5]\.` and `2A\.[1-5] — `) still bound the
# same span and need no edit; only the enumerated loop and the expected count follow the
# deletion. Renumbering 5 to 3 would silently rewrite the `terminology-binding` mapping.
scope2a_section=$(awk '/^### Scope 2A/{f=1} f && /^## Scope 3/{f=0} f' "$SCOPES")
crit_sev=$(printf '%s\n' "$scope2a_section" | $GREP -oE '^[1-5]\.|Severity: \*\*[A-Za-z]+\*\*' \
    | sed 's/\*//g' | paste -d' ' - - | sort -n | sed -E 's/^[0-9]+\. //')
# Codex bullet severities: extracted per criterion number rather than by a single regex
# spanning "(2A.N, appendix only) ... Severity: X" — greedy `.*` between the tag and the
# severity crosses the first unrelated period in the bullet's own prose (e.g. "spec.md"),
# so it never reaches the real "Severity:" token.
bullet_sev=""
for n in 1 2 5; do
    line=$($GREP -E "\(2A\.$n, appendix only\)" "$SCOPES")
    sev=$(printf '%s' "$line" | $GREP -oE 'Severity: [A-Za-z]+' | tail -1)
    bullet_sev="$bullet_sev$sev
"
done
bullet_sev=$(printf '%s' "$bullet_sev" | sed '/^$/d')
label_rows=$($GREP -oE '2A\.[1-5] — ' "$SCOPES" | sort -u)
n_crit=$(printf '%s\n' "$crit_sev" | $GREP -c . || true)
# Counted from the file, not from the loop above. Deriving this count from `for n in 1 2 5`
# made it measure the loop instead of the document: a leftover bullet for a deleted criterion
# is invisible to it, so the partial deletion this assertion exists to catch passed green.
# `n_label` was already an unbounded scan; this is the same shape.
n_bullet=$($GREP -cE '\(2A\.[0-9]+, appendix only\)' "$SCOPES" || true)
n_label=$(printf '%s\n' "$label_rows" | $GREP -c . || true)
if [ "$n_crit" -ne 3 ] || [ "$n_bullet" -ne 3 ] || [ "$n_label" -ne 3 ]; then
    fail "Scope 2A has 3 criteria, 3 Codex bullets, and 3 label-mapping rows" \
         "criteria=$n_crit bullets=$n_bullet label-rows=$n_label"
elif [ "$crit_sev" = "$bullet_sev" ]; then
    pass "Scope 2A's 3 criteria, Codex bullets, and label-mapping rows agree in count and severity"
else
    fail "Scope 2A's 3 criteria, Codex bullets, and label-mapping rows agree in count and severity" \
         "$(diff <(printf '%s\n' "$crit_sev") <(printf '%s\n' "$bullet_sev"))"
fi

echo "== Templates named in CLAUDE.md's numbered-heading exemption exist =="

# CLAUDE.md's Markdown Writing section names four templates as the sole exemption to the
# unnumbered-heading rule. Nothing checked that the named files actually exist, so a typo'd
# or renamed template (e.g. APPENDIX-FACT-SPEC-TEMPLATE.md for the real
# APPENDIX-SPEC-TEMPLATE.md) would silently exempt the wrong file and un-exempt the right one.
CLAUDE_MD="$CLAUDE/CLAUDE.md"
tmpl_line=$($GREP -m1 -F 'The only exceptions are docs generated from' "$CLAUDE_MD")
tmpl_names=$(printf '%s' "$tmpl_line" | $GREP -oE '[A-Z][A-Z-]*TEMPLATE\.md')
n_tmpl_names=$(printf '%s\n' "$tmpl_names" | $GREP -c . || true)
if [ "$n_tmpl_names" -eq 0 ]; then
    fail "template names extracted from CLAUDE.md's numbered-heading exemption" "extraction found none — sentence may have changed"
else
    absent=""
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        found=$(find "$CLAUDE" -name "$name" 2>/dev/null | head -1)
        [ -z "$found" ] && absent="$absent$name\n"
    done <<EOF
$tmpl_names
EOF
    if [ -z "$absent" ]; then
        pass "all $n_tmpl_names template(s) named in CLAUDE.md's numbered-heading exemption exist"
    else
        fail "all template(s) named in CLAUDE.md's numbered-heading exemption exist" "$(printf "%b" "$absent")"
    fi
fi

echo "== Codex quality-attributes SKILL.md carries the widened Minimality item (I5 / FR-5) =="

# codex-flow review runs with --ignore-user-config --ignore-rules and reads only bundled
# resources plus the request document, so this file is the only place a Codex design or code
# review ever sees the widened Minimality criterion.
#
# H3: a single anchor on the trailing "flag what serves neither" clause does not separate the
# widened form from a reversion to public-API-surface-only scope — that reversion keeps the
# same trailing clause, so the old single-phrase check stayed green on it. Require BOTH scope
# clauses the widening adds: the mechanism-wide one and the implementation-wide one. Dropping
# either half, or reducing the whole item to the bare noun "minimality", now fails; the two
# markers are otherwise stable text, independent of which noun phrase follows "no larger than".
#
# Bound to the "- minimality:" bullet line itself, not a whole-file search: this file also
# carries a disclosure sentence (M9) that names both clause phrases in prose to explain what
# this check binds to, and a whole-file grep is satisfied by that sentence even when the
# bullet above it is reduced to a bare noun or reverted — the exact vacuous-check shape this
# finding exists to close.
QA_SKILL="$ROOT/tools/codex-flow/codex_flow/resources/skills/domains/quality-attributes/SKILL.md"
if [ ! -f "$QA_SKILL" ]; then
    fail "quality-attributes SKILL.md carries the widened Minimality item, not a bare noun" \
         "file not found: $QA_SKILL"
else
    min_line=$($GREP -m1 -E '^- minimality:' "$QA_SKILL")
    if [ -n "$min_line" ] \
       && printf '%s' "$min_line" | $GREP -qF 'the mechanism is no larger than' \
       && printf '%s' "$min_line" | $GREP -qF 'the implementation is no larger than the approved design requires'; then
        pass "quality-attributes SKILL.md carries the widened Minimality item, not a bare noun"
    else
        fail "quality-attributes SKILL.md carries the widened Minimality item, not a bare noun" \
             "the '- minimality:' bullet line ('$min_line') must carry both scope clauses ('the mechanism is no larger than ...' and 'the implementation is no larger than the approved design requires') — mirror absent, reduced to a bare noun, or reverted to public-API-surface-only scope"
    fi
fi

echo "== doc-metrics: shipped corpus measures, and the published constants match the package =="

# The `doc-metrics` command (tools/docgate) owns the detector list, the accepted From: values
# and every threshold; this config publishes prose copies of the first two. Both mirrors were
# guarded by tests/verify-doc-metrics.sh, which was retired with the shell script it tested —
# its unit coverage moved to tools/docgate/tests/ and its cross-file assertions moved here.
#
# The Python side is read BY IMPORT, never by re-parsing the source: an assertion that greps
# metrics.py pins a source line, while an import pins the value the tool actually uses.
DESIGN_TEMPLATE="$CLAUDE/skills/workflows/planning/DESIGN-TEMPLATE.md"
AGENT_DOC="$CLAUDE/agents/architecture-research-planner.md"
CODEX_DOC="$ROOT/platforms/codex/skills/architecture-research-planner/SKILL.md"

# Value of a `NAME: <n> ...` summary line in doc-metrics output. Empty when the command did
# not run at all, which every caller below treats as a failure rather than as a zero.
metric() { printf '%s\n' "$1" | $GREP -m1 "^$2:" | awk '{print $2}'; }

# I1: the shipped template is the mechanism's own dogfood case — every Cost:/Misses: field is
# present, every requirement bullet carries a real From: tag, and the prose trips no register
# detector. L1 (code review main-2b1a277): this loop covered COST/MISSES/FROM/UNTAGGED only, so a
# REGISTER hit (a "deliberately" that snuck into §6) stayed green here even though the template
# itself violates the rule its own tool enforces.
tmpl_out=$(doc-metrics "$DESIGN_TEMPLATE" 2>&1); tmpl_rc=$?
bad=""
[ "$tmpl_rc" -eq 0 ] || bad="doc-metrics exited $tmpl_rc; "
for counter in COST MISSES FROM UNTAGGED REGISTER; do
    v=$(metric "$tmpl_out" "$counter")
    [ "$v" = "0" ] || bad="$bad$counter=${v:-<no line>}; "
done
if [ -z "$bad" ]; then
    pass "the shipped DESIGN-TEMPLATE.md reports zero on all five design-field/register counters"
else
    fail "the shipped DESIGN-TEMPLATE.md reports zero on all five design-field/register counters" \
         "$bad$(printf '\n%s' "$tmpl_out" | tail -8)"
fi

# I2: three copies of the detector list — the package constant plus the two authoring skills.
# Discovery is by the loose `deliberately|...` line shape, so a fourth publication site joins
# the comparison by existing rather than by being remembered; the exact-match count then
# catches a detector added to one copy alone, in either direction.
detector_list=$(python3 -c 'from docgate.metrics import REGISTER_DETECTOR_LIST; print(REGISTER_DETECTOR_LIST)' 2>/dev/null)
if [ -z "$detector_list" ]; then
    fail "the detector list is published verbatim in exactly the two authoring skills" \
         "importing REGISTER_DETECTOR_LIST from docgate.metrics produced nothing — is tools/docgate installed?"
else
    bad=""
    for doc in "$AGENT_DOC" "$CODEX_DOC"; do
        n=$($GREP -c -x -F "$detector_list" "$doc" || true)
        [ "$n" = "1" ] || bad="$bad${doc#"$ROOT"/}: $n verbatim copy(ies), want 1; "
    done
    declared=$(printf '%s\n%s\n' "${AGENT_DOC#"$ROOT"/}" "${CODEX_DOC#"$ROOT"/}" | sort)
    discovered=$($GREP -rl -xE 'deliberately\|.*' --include='*.md' "$ROOT/platforms" 2>/dev/null \
        | sed "s#^$ROOT/##" | sort)
    [ "$declared" = "$discovered" ] || bad="${bad}publication sites differ: $(diff <(printf '%s\n' "$declared") <(printf '%s\n' "$discovered") | tr '\n' ' '); "
    if [ -z "$bad" ]; then
        pass "the detector list imported from docgate.metrics is published verbatim, exactly once, in exactly the two authoring skills"
    else
        fail "the detector list imported from docgate.metrics is published verbatim, exactly once, in exactly the two authoring skills" "$bad"
    fi
fi

# I3: the five From: values are documented once, in DESIGN-TEMPLATE.md §3 guidance. Extraction
# is bound to the "Five values" line alone — the same paragraph carries an earlier `From:`
# mention and the adjacent decision-vs-analysis line repeats `analysis` and adds `assumption`,
# either of which a read of every backtick token in the guidance would miscount as a sixth.
pkg_from=$(python3 -c 'from docgate.metrics import FROM_VALUE_KINDS; print("\n".join(sorted(FROM_VALUE_KINDS)))' 2>/dev/null)
tmpl_line=$($GREP -m1 -F 'Five values,' "$DESIGN_TEMPLATE")
if [ -z "$pkg_from" ]; then
    fail "the From: value list in DESIGN-TEMPLATE.md §3 equals docgate.metrics' accepted set" \
         "importing FROM_VALUE_KINDS from docgate.metrics produced nothing — is tools/docgate installed?"
elif [ -z "$tmpl_line" ]; then
    fail "the From: value list in DESIGN-TEMPLATE.md §3 equals docgate.metrics' accepted set" \
         "no 'Five values,' line found in ${DESIGN_TEMPLATE#"$ROOT"/}"
else
    tmpl_from=$(printf '%s' "$tmpl_line" | $GREP -oE '`[a-z]+' | tr -d '`' | sort -u)
    if [ "$tmpl_from" = "$pkg_from" ]; then
        pass "the From: value list in DESIGN-TEMPLATE.md §3 equals docgate.metrics' accepted set"
    else
        fail "the From: value list in DESIGN-TEMPLATE.md §3 equals docgate.metrics' accepted set" \
             "$(diff <(printf '%s\n' "$tmpl_from") <(printf '%s\n' "$pkg_from") | sed 's/^</  only in template: /; s/^>/  only in package: /')"
    fi
fi

# I4: the corpus this tool governs must itself be measurable. Four config files once carried a
# ``` block nesting another ```, which inverts fence parity and makes the run exit BLOCKER —
# invisible in review, since an unbalanced fence reads as ordinary Markdown.
#
# The `== <path> ==` header count is asserted alongside the exit code because exit 0 and zero
# BLOCKERs are also what a tool that measured NOTHING reports: a stub exiting 0, or one that
# only ever reads its first argument, passes the other two checks unchanged.
corpus_files=()
while IFS= read -r -d '' f; do corpus_files+=("$f"); done \
    < <(find "$ROOT/platforms" -name '*.md' -print0 | sort -z)
if [ "${#corpus_files[@]}" -eq 0 ]; then
    fail "every Markdown file under platforms/ measures at exit 0" "found no .md files under platforms/"
else
    out=$(doc-metrics "${corpus_files[@]}" 2>&1); rc=$?
    blockers=$(printf '%s\n' "$out" | $GREP -c '^BLOCKER' || true)
    measured=$(printf '%s\n' "$out" | $GREP -c '^== ' || true)
    if [ "$rc" -eq 0 ] && [ "$blockers" -eq 0 ] && [ "$measured" -eq "${#corpus_files[@]}" ]; then
        pass "all ${#corpus_files[@]} Markdown file(s) under platforms/ measure at exit 0"
    else
        fail "all ${#corpus_files[@]} Markdown file(s) under platforms/ measure at exit 0" \
             "exit=$rc, $blockers BLOCKER line(s), $measured of ${#corpus_files[@]} measured: $(printf '%s\n' "$out" | $GREP '^BLOCKER' | head -5)"
    fi
fi

# I5: the tool is a command on PATH, not a script under ~/.claude/scripts/. A site left on the
# old name is silently un-runnable after tools/docgate replaces it, so check both halves: every
# invoking site carries the bare command, and the retired filename appears nowhere.
invoking_sites="commands/verify-docs.md commands/design.md commands/review-design-fix-loop.md agents/architecture-research-planner.md skills/workflows/planning/DESIGN-TEMPLATE.md"
bad=""
n_invoking=0
for rel in $invoking_sites; do
    n_invoking=$((n_invoking + 1))
    $GREP -qE '(^|[[:space:]`])doc-metrics([[:space:]`]|$)' "$CLAUDE/$rel" \
        || bad="$bad$rel (no bare \`doc-metrics\` invocation); "
done
old_name=$($GREP -rl 'doc-metrics\.sh' "$ROOT/platforms" 2>/dev/null | sed "s#^$ROOT/##" | tr '\n' ' ')
[ -n "$old_name" ] && bad="${bad}retired filename doc-metrics.sh still named in: $old_name"
if [ -z "$bad" ]; then
    pass "all $n_invoking invoking site(s) call the bare doc-metrics command, and doc-metrics.sh is named nowhere under platforms/"
else
    fail "all $n_invoking invoking site(s) call the bare doc-metrics command, and doc-metrics.sh is named nowhere under platforms/" "$bad"
fi

# I6: the agent doc fences its own detector list so publishing it is a mention, not a use.
# I4 only proves the file measures; nothing else proves the fence still holds.
agent_out=$(doc-metrics "$AGENT_DOC" 2>&1)
agent_reg=$(metric "$agent_out" REGISTER)
if [ "$agent_reg" = "0" ]; then
    pass "the agent doc publishing the detector list does not trip its own detector"
else
    fail "the agent doc publishing the detector list does not trip its own detector" \
         "REGISTER=${agent_reg:-<no line>} :: $(printf '%s\n' "$agent_out" | tail -8)"
fi

# === Discovered-work scope ask (mechanism-proportionality step 3a) =========================
#
# One rule, two implementation paths that cannot see each other: agents/coder.md reaches no
# Codex path (build_implementation_prompt loads six bundled resources and that file is not
# among them), and the bundled resource is outside sync-configs.sh's include list. So the
# only thing holding the two copies together is these two assertions.
#
# Both bind to the clause, not the file. A file-level grep for "discovered work" is satisfied
# by any prose mentioning it — including a comment like this one — which is the defect four
# review rounds of step 2 kept finding.

CODER_DOC="$CLAUDE/agents/coder.md"
EXT_IMPL="$ROOT/tools/codex-flow/codex_flow/resources/skills/workflows/external-implementation/SKILL.md"

# S1: coder.md item 3 carries both halves on the item line — the origin-independent scope
# rule and the size figure. A reversion to "matches the approved design (no scope creep)"
# keeps the noun "scope" and loses both.
item3=$($GREP -m 1 '^3\. \*\*Scope:\*\*' "$CODER_DOC" || true)
if [ -n "$item3" ] \
    && printf '%s' "$item3" | $GREP -q 'whether or not you originated it' \
    && printf '%s' "$item3" | $GREP -q 'git diff --stat'; then
    pass "coder.md item 3 carries the origin-independent scope rule and the size figure"
else
    fail "coder.md item 3 carries the origin-independent scope rule and the size figure" \
         "item 3 line: ${item3:-<no '3. **Scope:**' line found>}"
fi

# S2: the bundled mirror carries the same rule and routes it to open_issues on the prefix
# line itself. That file already has four other open_issues sentences, so a file-level check
# for the token would stay green with this one deleted.
ext_line=$($GREP -m 1 'Scope: BLOCKED' "$EXT_IMPL" || true)
if [ -n "$ext_line" ] \
    && printf '%s' "$ext_line" | $GREP -q 'open_issues' \
    && $GREP -q 'whether or not you originated it' "$EXT_IMPL"; then
    pass "the bundled external-implementation skill mirrors the scope ask and routes it to open_issues"
else
    fail "the bundled external-implementation skill mirrors the scope ask and routes it to open_issues" \
         "Scope: BLOCKED line: ${ext_line:-<not found>}"
fi

# S3: /verify's attribution step (step 3b). Span-scoped, not file-scoped — `verify.md` already
# carries `git diff` and `origin/master` elsewhere (step 2a), so a file-level grep for either
# proves nothing about this step. The span runs from the step 8 opener to the next numbered step
# (`/^9\. /`), not the next `## ` — mechanism-proportionality step 7 inserts step 9 (the
# comment-gate run) between step 8 and the next heading, and a `^## ` terminator would swallow
# it, letting step 9's own copy of `refs/remotes/origin/HEAD` keep this assertion green after
# step 8's own resolution line was deleted. Also pins the `BASE=` assignment itself (not just the
# resolution token it fixes) and asserts step 9's content — the comment-gate invocation — has not
# leaked into step 8's own span.
VERIFY_DOC="$CLAUDE/commands/verify.md"
span=$(awk '/^8\. \*\*Attribution/{f=1} f&&/^9\. /{exit} f' "$VERIFY_DOC")
s3_bad=""
if [ -z "$span" ]; then
    s3_bad="no step 8 span found; "
else
    printf '%s' "$span" | $GREP -q 'refs/remotes/origin/HEAD' \
        || s3_bad="${s3_bad}span missing 'refs/remotes/origin/HEAD'; "
    printf '%s' "$span" | $GREP -q 'ls-files --others' \
        || s3_bad="${s3_bad}span missing 'ls-files --others'; "
    printf '%s' "$span" | $GREP -q 'say so in one line' \
        || s3_bad="${s3_bad}span missing 'say so in one line'; "
    printf '%s' "$span" | $GREP -qF 'BASE=$(git symbolic-ref' \
        || s3_bad="${s3_bad}span missing 'BASE=\$(git symbolic-ref'; "
    printf '%s' "$span" | $GREP -qF 'comment-gate.sh' \
        && s3_bad="${s3_bad}comment-gate.sh leaked into step 8's span from step 9; "
fi
if [ -z "$s3_bad" ]; then
    pass "/verify's attribution step resolves the base, sees unstaged files, documents the no-source skip, and carries no comment-gate.sh leaked in from step 9"
else
    fail "/verify's attribution step resolves the base, sees unstaged files, documents the no-source skip, and carries no comment-gate.sh leaked in from step 9" "$s3_bad"
fi

# S4: diagnose.md Step 5's attribution check (step 3c). Bound to the bullet, not the file --
# "Belongs to" also appears in this suite's own comments and could appear in Step 6's prose.
# The withhold-nothing rule is the load-bearing half: an earlier design dropped the entry, and
# three reviewers rated losing a real observed failure as High.
DIAGNOSE_DOC="$CLAUDE/commands/diagnose.md"
bullet=$(awk '/Check the root cause against this work/{f=1} f{print; exit}' "$DIAGNOSE_DOC")
if [ -n "$bullet" ] \
    && printf '%s' "$bullet" | $GREP -q '\*\*Belongs to:\*\*' \
    && printf '%s' "$bullet" | $GREP -q 'Still write the entry'; then
    pass "diagnose.md Step 5 attributes a root cause and still records it when it belongs elsewhere"
else
    fail "diagnose.md Step 5 attributes a root cause and still records it when it belongs elsewhere" \
         "bullet: ${bullet:-<no attribution bullet found>}"
fi

# === Trigger-6 deletion and the closed list (mechanism-proportionality step 4) ============
#
# design.md §6 T1-T6. Trigger 6 (a review finding confirmed to reproduce) is deleted from the
# observed-failure trigger list; item 3 absorbs its admission predicate as a run criterion that
# reaches every consumer, including the ones outside the fragment's `Read` reach. The gate also
# gains a representable no-test outcome — a closed list of four `### Out of Scope` clauses plus
# six waiver categories — and the three "no Critical/High finding is fixed without a test"
# clauses yield to a discharge stated in the coder's fix response. Six assertions, each bound to
# a literal or a section, not to prose that could be reworded without changing behaviour.

CODEX_DIR="$ROOT/platforms/codex"
SRC_RT="$CLAUDE/skills/workflows/regression-test/SKILL.md"
CHECKLIST="$CLAUDE/skills/domains/quality-attributes/references/review-checklist.md"
# F13: defined again here, beside the two fragments this whole block reads, rather than relying
# on the copy an unrelated block up-file happens to set — that copy exists for its own assertion,
# and reordering blocks would abort this one under `set -u` far from the actual fault.
VERIFY_DOC="$CLAUDE/commands/verify.md"
# F14: arrays, not space-joined strings — a path containing whitespace would silently word-split
# wrong under the old form, and every consumer below already needs `"${T1_ROOTS[@]}"` quoting.
T1_ROOTS=("$ROOT/platforms" "$ROOT/tools/codex-flow/codex_flow/resources")

echo "== T1: the eight struck trigger-6 literals occur nowhere under the config roots, over a non-empty, existing corpus =="

# T1: deleting trigger 6 must not leave any of its own wording, or the two literals it carried,
# behind at the five sites §5 rewrites plus the fragment's own "only alternative" framing
# (repeated at two more files). Roots exclude tests/ deliberately — this comment and the ones
# below quote the forbidden literals for documentation, and a self-referential red here would
# make the assertion unmaintainable.
#
# F5: an absence-only scan has no positive control — typo both roots and every literal still
# reads "absent" over a corpus that was never searched. Assert the roots resolve to directories
# and that the scan actually walked a non-zero number of files before trusting the negative result.
t1_bad=""
for r in "${T1_ROOTS[@]}"; do
    [ -d "$r" ] || t1_bad="${t1_bad}root '$r' is not a directory — the corpus scan would run over nothing; "
done
n_t1_scanned=$(find "${T1_ROOTS[@]}" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$n_t1_scanned" -gt 0 ] || t1_bad="${t1_bad}0 Markdown files found under the config roots — the corpus scan ran over nothing; "

# F11: the pass message names how many literals were checked, counted from the list itself
# rather than hand-copied, so the two cannot drift apart.
t1_literals=(
    "confirmed to reproduce" "trigger 6" "only alternative" "review finding H3"
    "not an observed failure at all" "flags a missing ledger entry as High"
    "cannot clear re-review" "a prior review report in the issue folder"
)
# F10: the failure detail keeps the count (useful at a glance) and now also appends the
# file:line hits already in hand instead of discarding them — T4's loop below already does this.
for lit in "${t1_literals[@]}"; do
    hits=$($GREP -rniF "$lit" "${T1_ROOTS[@]}" 2>/dev/null || true)
    [ -n "$hits" ] && t1_bad="$t1_bad'$lit': $(printf '%s\n' "$hits" | wc -l) occurrence(s) — $(printf '%s' "$hits" | tr '\n' ' '); "
done
if [ -z "$t1_bad" ]; then
    pass "both config roots exist, $n_t1_scanned Markdown file(s) are in scope, and none of the ${#t1_literals[@]} struck trigger-6 literals occur under them"
else
    fail "both config roots exist, a non-empty corpus is in scope, and none of the ${#t1_literals[@]} struck trigger-6 literals occur under them" "$t1_bad"
fi

echo "== T2: the trigger list closes at five, and item 3's run criterion reaches all six routed sites =="

# T2: item 3's widening is the replacement admission predicate. Checked per delivery route, not
# per file — a route left on the old review-finding-specific wording still fires trigger 6's
# behaviour on whichever consumer reads it, invisibly. The unit is the numbered item or the
# mirrored statement, matched case-sensitively, with an absence half on the same unit.
RUN_CRITERION="reproduced by running the code"
# H3: the routed-site half below used to accept the criterion on ANY line of the file, which a
# strike-and-park mutation satisfies by leaving the bare substring in unrelated prose (proven at
# testing/SKILL.md and the bundled code-review/SKILL.md) while the real trigger list no longer
# carries it. Anchor on a stable token that co-occurs with the criterion at every site in the
# design's own replacement text ("...reproduced by running the code, whoever reported it
# first") and require both on the SAME line — the same binding T2 already does for source item
# 3 via the numbered-item extraction.
RUN_ANCHOR="whoever reported it first"
t2_bad=""
owcf=$(awk '/^## What Counts as an Observed Failure/{f=1;next} f && /^### /{exit} f' "$SRC_RT")
# H3: a sixth trigger item shipped as a bullet, or indented, is invisible to a bare `^[0-9]+\. `
# count — widen to any list-item shape so an evasion by formatting still moves the count off 5.
n_items=$(printf '%s\n' "$owcf" | $GREP -cE '^[ ]*([0-9]+\.|[-*+]) +')
highest=$(printf '%s\n' "$owcf" | $GREP -oE '^[0-9]+' | sort -n | tail -1)
item3=$(printf '%s\n' "$owcf" | $GREP -m1 -E '^3\. ')
[ "$n_items" -eq 5 ] || t2_bad="${t2_bad}trigger list has $n_items items, want 5; "
[ "$highest" = "5" ] || t2_bad="${t2_bad}trigger list's highest ordinal is '$highest', want 5; "
printf '%s' "$item3" | $GREP -qF "$RUN_CRITERION" || t2_bad="${t2_bad}source item 3 does not carry '$RUN_CRITERION'; "
printf '%s' "$item3" | $GREP -q 'review finding' && t2_bad="${t2_bad}source item 3 still names 'review finding'; "

routed_sites=(
    "$CHECKLIST"
    "$CODEX_DIR/CODEX.md"
    "$CODEX_DIR/skills/domains/testing/SKILL.md"
    "$CODEX_DIR/skills/domains/code-quality/references/code-review-checklist.md"
    "$ROOT/tools/codex-flow/codex_flow/resources/skills/workflows/code-review/SKILL.md"
    "$ROOT/tools/codex-flow/codex_flow/resources/skills/workflows/external-implementation/SKILL.md"
)
# H2: each site's own trigger-statement opener, positionally paired with routed_sites above. A
# same-line criterion+anchor check alone is satisfied by a decoy occurrence anywhere in the file
# — C7 only forbids quoting absence-half literals, so a disclosure sentence quoting the run
# criterion is a realistic decoy — so the criterion's one surviving occurrence must also fall on
# its own site's real trigger statement, not merely co-occur with the anchor somewhere else.
routed_anchors=(
    "Determine whether the diff fixes a failure"
    "**Observed-failure regression pass:**"
    "Add a deterministic regression test"
    "Every failure that actually occurred"
    "Determine whether the change fixes a failure"
    "When the implementation fixes a failure"
)
# F12: `n_routed` used to just count words in a static list — a tautology that always equalled
# 6 regardless of the corpus. It now only increments when the file genuinely exists and is
# non-empty, so a deleted or emptied site drops the count and fails structurally.
n_routed=0
for i in "${!routed_sites[@]}"; do
    f="${routed_sites[$i]}"
    opener="${routed_anchors[$i]}"
    if [ ! -s "$f" ]; then
        t2_bad="${t2_bad}${f#"$ROOT"/}: file missing or empty — the routed-site scan ran over nothing; "
        continue
    fi
    n_routed=$((n_routed + 1))
    # H2: exactly one occurrence in the whole file — a strike-and-park mutation that guts the
    # real trigger statement but leaves (or adds) the criterion elsewhere, e.g. quoted in a C7
    # disclosure, pushes this off 1 even when that surviving occurrence sits beside the anchor.
    crit_count=$($GREP -cF "$RUN_CRITERION" "$f" || true)
    if [ "$crit_count" -ne 1 ]; then
        t2_bad="${t2_bad}${f#"$ROOT"/}: '$RUN_CRITERION' occurs $crit_count time(s), want exactly 1 — a decoy occurrence can hide a gutted trigger statement; "
        continue
    fi
    line=$($GREP -F "$RUN_CRITERION" "$f")
    if ! printf '%s' "$line" | $GREP -qF "$RUN_ANCHOR"; then
        t2_bad="${t2_bad}${f#"$ROOT"/}: does not carry '$RUN_CRITERION' with '$RUN_ANCHOR' on the same line — the criterion may be parked in unrelated prose; "
    fi
    if ! printf '%s' "$line" | $GREP -qF "$opener"; then
        t2_bad="${t2_bad}${f#"$ROOT"/}: the criterion's line does not carry its own trigger statement's opener ('$opener') — the criterion may have been relocated away from the real trigger statement; "
    fi
    printf '%s' "$line" | $GREP -q 'review finding' && t2_bad="${t2_bad}${f#"$ROOT"/}: still names 'review finding' on that line; "
done

obs_line=$($GREP -m1 -F '**Observed in:**' "$SRC_RT")
printf '%s' "$obs_line" | $GREP -qF 'the run that reproduced it' \
    || t2_bad="${t2_bad}Observed in template line does not carry 'the run that reproduced it'; "

if [ "$n_routed" -eq 6 ] && [ -z "$t2_bad" ]; then
    pass "the trigger list closes at five, item 3 carries the run criterion at the source and all $n_routed routed sites, and no unit names 'review finding'"
else
    fail "the trigger list closes at five, item 3 carries the run criterion at the source and all routed sites, and no unit names 'review finding'" "routed=$n_routed; $t2_bad"
fi

echo "== T3: the closed list, the Rule/Waiver discharge pins, the checklist mirror, and verify.md's re-resolution =="

# T3: one assertion spanning every site the closed list touches — the four `### Out of Scope`
# clauses and their two decidable tests, the closure sentence's three literals, `## Rule` and
# `## Waiver`'s discharge-set pin, review-checklist.md's mirror, and verify.md Step 6c/6d's
# ordered re-resolution replacing the old in-place `out-of-scope` grant.
t3_bad=""
oos_section=$(awk '/^### Out of Scope/{f=1;next} f && /^## /{exit} f' "$SRC_RT")
# F1: `^- \*\*[A-Z]` misses a lowercase-titled or `*`-bulleted fifth clause, so a mutation that
# adds one in either shape leaves the count reading 4 undisturbed. Widen the count to any bullet
# marker followed by a bold run, so an added clause is counted regardless of its own formatting.
# H3: F1's fix still required the bold run — a seventh clause added indented or unbolded still
# passed. Count any list-item shape (any marker, indented, bold or not) instead.
# H1 (round 3): the widened pattern still required a bullet marker (-, *, +) and missed the
# numbered-item alternation its three siblings (n_items, n_cats, n_steps) already carry — a
# fifth clause shipped as a numbered item (5. **Superseded coverage** — ...) was invisible to
# it and the count still read 4.
n_clauses=$(printf '%s\n' "$oos_section" | $GREP -cE '^[ ]*([0-9]+\.|[-*+]) +')
[ "$n_clauses" -eq 4 ] || t3_bad="${t3_bad}### Out of Scope has $n_clauses clause bullets, want 4; "

# F1 / F9: each clause's own bullet line, extracted by its exact title — this both asserts the
# title is present *in the source* (previously pinned only in the checklist mirror below) and
# gives each clause-body literal a line to bind to, so a literal migrated to the wrong clause, or
# a clause renamed out from under its sentence, is caught instead of passing on a section-wide
# grep that cannot tell which bullet supplied the match.
no_repo_line=$($GREP -m1 -E '^- \*\*No repository component\*\*' "$SRC_RT")
nothing_line=$($GREP -m1 -E '^- \*\*Nothing assertable changed\*\*' "$SRC_RT")
thirdparty_line=$($GREP -m1 -E '^- \*\*Third-party behaviour only\*\*' "$SRC_RT")
analysed_line=$($GREP -m1 -E '^- \*\*Analysed, did not reproduce\*\*' "$SRC_RT")
[ -n "$no_repo_line" ] || t3_bad="${t3_bad}### Out of Scope missing the 'No repository component' bullet; "
[ -n "$nothing_line" ] || t3_bad="${t3_bad}### Out of Scope missing the 'Nothing assertable changed' bullet; "
[ -n "$thirdparty_line" ] || t3_bad="${t3_bad}### Out of Scope missing the 'Third-party behaviour only' bullet; "
[ -n "$analysed_line" ] || t3_bad="${t3_bad}### Out of Scope missing the 'Analysed, did not reproduce' bullet; "
printf '%s' "$nothing_line" | $GREP -qF 'leaves nothing assertable' \
    || t3_bad="${t3_bad}Nothing assertable changed does not carry the fix-by-deletion sentence in its own bullet; "
printf '%s' "$thirdparty_line" | $GREP -qF 'no line of repository code between the input and the assertion' \
    || t3_bad="${t3_bad}Third-party behaviour only missing its structural test in its own bullet; "
printf '%s' "$analysed_line" | $GREP -qF '<what was reported> — analysed, does not reproduce:' \
    || t3_bad="${t3_bad}Analysed, did not reproduce missing its Reason template in its own bullet; "

closure=$($GREP -m1 -F 'the complete set of self-service' "$SRC_RT")
printf '%s' "$closure" | $GREP -qF 'names the clause it claims' || t3_bad="${t3_bad}closure sentence missing 'names the clause it claims'; "
printf '%s' "$closure" | $GREP -qF 'one of the six categories' || t3_bad="${t3_bad}closure sentence missing 'one of the six categories'; "
printf '%s' "$closure" | $GREP -qF 'the closed list' || t3_bad="${t3_bad}closure sentence missing 'the closed list'; "

rule_sec=$(awk '/^## Rule/{f=1;next} f && /^## /{exit} f' "$SRC_RT")
waiver_sec=$(awk '/^## Waiver/{f=1;next} f && /^## /{exit} f' "$SRC_RT")
printf '%s\n' "$rule_sec" | $GREP -qF 'a test, a named clause, or an approved waiver' \
    || t3_bad="${t3_bad}## Rule does not carry the full discharge set; "
printf '%s\n' "$waiver_sec" | $GREP -qF 'a test, a named clause, or an approved waiver' \
    || t3_bad="${t3_bad}## Waiver does not carry the full discharge set; "
# H4: the green-re-run paragraph's old exclusive sentence contradicted the three-way closure
# stated two sentences above it in the same section — guard against its reintroduction now that
# the replacement scopes it to the test arm.
printf '%s\n' "$rule_sec" | $GREP -qF 'Only a test that asserts the specific symptom closes the gate' \
    && t3_bad="${t3_bad}## Rule still carries the old exclusive green-re-run sentence ('...closes the gate' unscoped to the test arm); "

# F8: the design and the shipped disclosure both say "this step" — review-checklist.md's Test
# Quality Pass Step 3, not the file at large. A file-wide grep is satisfied by the mirror
# relocated anywhere else in the file (probed: moving the whole block out of Step 3 still
# passes). Scope to the Step 3 span, from its own heading to the next mandatory pass.
checklist_step3=$(awk '/\*\*Step 3 — Observed-failure regression coverage:\*\*/{f=1;next} f && /^### Cross-Site Consistency Pass/{exit} f' "$CHECKLIST")
[ -n "$checklist_step3" ] || t3_bad="${t3_bad}review-checklist.md Test Quality Pass Step 3 extraction is empty — the heading anchor may have moved; "
for title in "No repository component" "Nothing assertable changed" "Third-party behaviour only" "Analysed, did not reproduce"; do
    printf '%s\n' "$checklist_step3" | $GREP -qF "$title" || t3_bad="${t3_bad}review-checklist.md Step 3 missing clause title '$title'; "
done
for cat in "unavailable environment" "harness or provider defect" "destructive reproduction" "non-deterministic race" "workflow-instruction defect" "vacuous test"; do
    printf '%s\n' "$checklist_step3" | $GREP -qiF "$cat" || t3_bad="${t3_bad}review-checklist.md Step 3 missing category name '$cat'; "
done
printf '%s\n' "$checklist_step3" | $GREP -qF 'behaviour the repository can assert on' \
    || t3_bad="${t3_bad}review-checklist.md Step 3 missing Nothing assertable changed's decidable test; "
printf '%s\n' "$checklist_step3" | $GREP -qF 'no line of repository code sits between the input and the assertion' \
    || t3_bad="${t3_bad}review-checklist.md Step 3 missing Third-party behaviour only's structural test; "

verify_6c=$(awk '/\*\*Step 6c/{f=1} f && /\*\*Step 6d/{exit} f' "$VERIFY_DOC")
verify_6d=$(awk '/\*\*Step 6d — On failure, BLOCK/{f=1} f && /^7\. \*\*On-device/{exit} f' "$VERIFY_DOC")
printf '%s\n' "$verify_6c" | $GREP -qF 'blank the **Test:** field' || t3_bad="${t3_bad}verify.md Step 6c missing 'blank the **Test:** field'; "
printf '%s\n' "$verify_6c" | $GREP -qF 're-resolve it through the closed list' || t3_bad="${t3_bad}verify.md Step 6c missing 're-resolve it through the closed list'; "
printf '%s\n' "$verify_6c" | $GREP -qF 'update the **Test:** field and stop' || t3_bad="${t3_bad}verify.md Step 6c missing 'update the **Test:** field and stop'; "
printf '%s\n' "$verify_6c" | $GREP -qF 'record the clause in place' || t3_bad="${t3_bad}verify.md Step 6c missing 'record the clause in place'; "
printf '%s\n' "$verify_6d" | $GREP -qF 're-resolve it through the closed list' || t3_bad="${t3_bad}verify.md Step 6d recovery missing 're-resolve it through the closed list'; "
printf '%s\n' "$verify_6d" | $GREP -qF "the issue's next" || t3_bad="${t3_bad}verify.md Step 6d recovery does not name the issue's-next owner; "
$GREP -qF 'in place to `out-of-scope`' "$VERIFY_DOC" && t3_bad="${t3_bad}verify.md still carries the old in-place out-of-scope grant; "

if [ -z "$t3_bad" ]; then
    pass "the closed list's four clauses, the closure sentence, the Rule/Waiver discharge pins, the checklist mirror, and verify.md's Step 6c/6d re-resolution are all present"
else
    fail "the closed list's four clauses, the closure sentence, the Rule/Waiver discharge pins, the checklist mirror, and verify.md's Step 6c/6d re-resolution are all present" "$t3_bad"
fi

echo "== T4: the waiver count reads six at every quantifying statement, with no five/four remnant =="

# T4: the unit is a statement, not a file — five statements sit in regression-test/SKILL.md
# alone (the template line, the opener, the list's own highest item, the awk pattern, and its
# BLOCKER message), one each in CLAUDE.md and testing/SKILL.md. The absence half reuses T1's
# roots.
t4_bad=""
n_t4_statements=0
$GREP -qF '6 vacuous-test>' "$SRC_RT" || t4_bad="${t4_bad}Waiver category template line's highest option is not 6; "
n_t4_statements=$((n_t4_statements + 1))
$GREP -qF 'these six is not valid' "$SRC_RT" || t4_bad="${t4_bad}Allowed categories opener does not read six; "
n_t4_statements=$((n_t4_statements + 1))
$GREP -qE '^6\. \*\*Vacuous test\*\*' "$SRC_RT" || t4_bad="${t4_bad}category list's highest item is not 6; "
n_t4_statements=$((n_t4_statements + 1))

# F2: a presence test on item 6 alone never notices a seventh category appended after it — the
# count statement would still read six while the list itself no longer closes at six. Bound the
# span to the enumeration itself (its own opener to the paragraph that follows the list) and
# assert both the item count and the highest ordinal inside it.
# H3: bounding to `**Allowed categories**`'s own span and requiring `^[0-9]+\. \*\*` still missed
# a seventh category placed after the span's end anchor (`Every waiver requires`, itself outside
# the count) or shaped as a bullet or indented line inside it. Count over the whole `## Waiver`
# section instead ($waiver_sec, already extracted above) with any list-item shape.
n_cats=$(printf '%s\n' "$waiver_sec" | $GREP -cE '^[ ]*([0-9]+\.|[-*+]) +')
highest_cat=$(printf '%s\n' "$waiver_sec" | $GREP -oE '^[ ]*[0-9]+' | sed 's/^ *//' | sort -n | tail -1)
[ "$n_cats" -eq 6 ] || t4_bad="${t4_bad}## Waiver section holds $n_cats list-item(s) (numbered, bulleted, or indented), want 6 waiver categories; "
[ "$highest_cat" = "6" ] || t4_bad="${t4_bad}## Waiver section's highest numbered-item ordinal is '$highest_cat', want 6; "
n_t4_statements=$((n_t4_statements + 1))

# F15: `[1-6]` and `1-6 —` used to be file-wide, so unrelated prose gaining either token later
# would false-red this check even though the hard gate itself is untouched. Bind both to the
# `## Hard Gate` fenced awk block specifically, the same fence-counting extraction this file
# already uses for the rejection-block check above.
hard_gate_fence=$(awk '
  /^## Hard Gate/ { f=1 }
  f && /^```/ { fence++; if (fence == 1) next; else exit }
  f && fence == 1 { print }
' "$SRC_RT")
[ -n "$hard_gate_fence" ] || t4_bad="${t4_bad}## Hard Gate fenced block extraction is empty — the fence anchor may have moved; "
printf '%s\n' "$hard_gate_fence" | $GREP -qF '[1-6]' || t4_bad="${t4_bad}hard-gate awk fence does not match [1-6]; "
n_t4_statements=$((n_t4_statements + 1))
printf '%s\n' "$hard_gate_fence" | $GREP -qF '1-6 —' || t4_bad="${t4_bad}hard-gate awk fence's BLOCKER message does not read 1-6; "
n_t4_statements=$((n_t4_statements + 1))

# F16: the two "gate closes on one of three" sentences (CLAUDE.md and testing/SKILL.md word the
# waiver clause slightly differently — "an approved waiver" vs. "a user-approved waiver") shipped
# with no assertion at all. Pin the shared prefix both wordings carry.
$GREP -qF 'one of six narrow categories' "$CLAUDE/CLAUDE.md" || t4_bad="${t4_bad}CLAUDE.md does not read six narrow categories; "
n_t4_statements=$((n_t4_statements + 1))
$GREP -qF 'one of six narrow categories' "$CLAUDE/skills/domains/testing/SKILL.md" || t4_bad="${t4_bad}testing/SKILL.md does not read six narrow categories; "
n_t4_statements=$((n_t4_statements + 1))
$GREP -qF 'The gate closes on one of three: a test, a named clause, or' "$CLAUDE/CLAUDE.md" \
    || t4_bad="${t4_bad}CLAUDE.md discharge-set sentence ('the gate closes on one of three...') is missing or reworded; "
$GREP -qF 'The gate closes on one of three: a test, a named clause, or' "$CLAUDE/skills/domains/testing/SKILL.md" \
    || t4_bad="${t4_bad}testing/SKILL.md discharge-set sentence ('the gate closes on one of three...') is missing or reworded; "

for lit in "these five" "five narrow categories" "four waiver categories"; do
    hits=$($GREP -rniF "$lit" "${T1_ROOTS[@]}" 2>/dev/null || true)
    [ -n "$hits" ] && t4_bad="${t4_bad}'$lit' still occurs: $(printf '%s' "$hits" | tr '\n' ' '); "
done
$GREP -rE 'Waiver category.*\[1-5\]' "${T1_ROOTS[@]}" >/dev/null 2>&1 && t4_bad="${t4_bad}a Waiver category reading [1-5] still exists; "
if [ -z "$t4_bad" ]; then
    pass "the waiver count reads six at all $n_t4_statements quantifying statements, the category list closes at 6, and no five/four remnant survives under the config roots"
else
    fail "the waiver count reads six at all $n_t4_statements quantifying statements, the category list closes at 6, and no five/four remnant survives under the config roots" "$t4_bad"
fi

echo "== T5: category 6's conditions and prohibition are mirrored in the checklist, and never self-serviced =="

# T5: the two inspectable conditions, the drift carve-out, and the control prohibition must
# survive at both the source and the pasted checklist copy — a mirror missing the carve-out
# would let the checklist classify the repository's own presence assertions as vacuous, and one
# missing the prohibition could accept a compensating control that is itself a test.
t5_bad=""
cat6=$($GREP -m1 -E '^6\. \*\*Vacuous test\*\*' "$SRC_RT")
for lit in "asserts the same expression the fix wrote" "mirrors the production control flow" "is not a restatement" "cannot be another test"; do
    printf '%s' "$cat6" | $GREP -qF "$lit" || t5_bad="${t5_bad}regression-test/SKILL.md category 6 missing '$lit'; "
done
# F8: bind to the same Step 3 span T3 extracts, not the whole checklist file.
for lit in "asserts the same expression the fix wrote" "mirrors the production control flow" "is not a restatement" "cannot be another test"; do
    printf '%s\n' "$checklist_step3" | $GREP -qF "$lit" || t5_bad="${t5_bad}review-checklist.md Step 3 missing '$lit'; "
done
# F7: re-extract `### Out of Scope` locally instead of reading T3's `$oos_section` — the two
# assertions used to share one extraction, so a break in T3's copy silently vacuous-passed this
# negative check too (an empty section contains no clause reading 'restates the implementation'
# either), and reordering the blocks would have made that failure mode invisible here.
t5_oos_section=$(awk '/^### Out of Scope/{f=1;next} f && /^## /{exit} f' "$SRC_RT")
[ -n "$t5_oos_section" ] || t5_bad="${t5_bad}### Out of Scope extraction is empty — cannot verify no clause admits a self-service vacuous-test exit; "
printf '%s\n' "$t5_oos_section" | $GREP -qF 'restates the implementation' \
    && t5_bad="${t5_bad}an ### Out of Scope clause reads 'restates the implementation' — the vacuous-test judgement has become self-service; "
if [ -z "$t5_bad" ]; then
    pass "category 6's two conditions, drift carve-out, and control prohibition are mirrored in review-checklist.md, and no Out of Scope clause admits a self-service vacuous-test exit"
else
    fail "category 6's two conditions, drift carve-out, and control prohibition are mirrored in review-checklist.md, and no Out of Scope clause admits a self-service vacuous-test exit" "$t5_bad"
fi

echo "== T6: the ordered check, the per-site discharge wording, the roster rewrite, and STILL OPEN's sole home =="

# T6: the widest single assertion — the four-step ordered check, the five discharge literals at
# each of the three proof-of-fix sites (with the old absolute mandate gone from all three), the
# Who-writes-it roster naming the loops as writers of a reproduced-defect entry, and STILL
# OPEN's case-sensitive scope: present only in review-iterate.md, and only from Step 2c onward.
t6_bad=""
bwt=$(awk '/^## Before Writing the Test/{f=1;next} f && /^## /{exit} f' "$SRC_RT")
step1=$(printf '%s\n' "$bwt" | $GREP -m1 -E '^1\. ')
step2=$(printf '%s\n' "$bwt" | $GREP -m1 -E '^2\. ')
step3=$(printf '%s\n' "$bwt" | $GREP -m1 -E '^3\. ')
step4=$(printf '%s\n' "$bwt" | $GREP -m1 -E '^4\. ')
# H3: a fifth step added as a bullet, or indented, is invisible to a bare `^[0-9]+\. ` count —
# widen to any list-item shape, same as T2's and T4's.
n_steps=$(printf '%s\n' "$bwt" | $GREP -cE '^[ ]*([0-9]+\.|[-*+]) +')
# F3: `n_steps -eq 4` plus first-line greps of steps 1-2 never looked at steps 3-4, so replacing
# either with "Reserved." — or renumbering the list 1,2,2,4 — still passed. Require the ordinal
# sequence itself, in order, and pin one literal per step.
ordinals=$(printf '%s\n' "$bwt" | $GREP -oE '^[0-9]+' | tr '\n' ' ' | sed 's/ $//')
[ "$n_steps" -eq 4 ] || t6_bad="${t6_bad}Before Writing the Test has $n_steps numbered steps, want 4; "
[ "$ordinals" = "1 2 3 4" ] || t6_bad="${t6_bad}Before Writing the Test's ordinal sequence is '$ordinals', want '1 2 3 4'; "
printf '%s' "$step1" | $GREP -qF 'Out of Scope' || t6_bad="${t6_bad}step 1 does not route the Out of Scope clauses; "
printf '%s' "$step1" | $GREP -qF 'six waiver' || t6_bad="${t6_bad}step 1 does not route all six waiver categories; "
printf '%s' "$step2" | $GREP -qF 'at the level the selection table names' || t6_bad="${t6_bad}step 2 missing 'at the level the selection table names'; "
printf '%s' "$step3" | $GREP -qF 'Consolidate near-duplicates' || t6_bad="${t6_bad}step 3 missing 'Consolidate near-duplicates'; "
printf '%s' "$step4" | $GREP -qF 'Otherwise write a new test' || t6_bad="${t6_bad}step 4 missing 'Otherwise write a new test'; "
printf '%s\n' "$bwt" | $GREP -qF 'An extended test satisfies' || t6_bad="${t6_bad}section missing 'An extended test satisfies'; "

REVITER="$CLAUDE/commands/review-iterate.md"
# F14: array, not a space-joined string — see T1_ROOTS above.
proof_sites=("$CLAUDE/commands/review-code-fix-loop.md" "$REVITER" "$CLAUDE/commands/review-fix.md")
for f in "${proof_sites[@]}"; do
    # F16: "The discharge governs the test, not the ledger." shipped at all three sites with no
    # assertion pinning it — added to the same per-site literal set the other four discharge
    # phrases already use.
    # H3: the no-self-serve body was pinned only by its bold lead ("Do not self-serve a
    # waiver") at all three sites — restoring round 2's inverted wording ("this command judges
    # it" / "record it yourself and proceed") after the bold lead left the suite green, since
    # nothing pinned the body's own who-decides clause. Add each site's literal.
    for lit in "unless a clause in" "the user has approved a waiver" "discharge retires the" \
               "State the discharge in your fix response" "Do not self-serve a waiver" \
               "The discharge governs the test, not the ledger." "decides outside"; do
        $GREP -qF "$lit" "$f" || t6_bad="${t6_bad}${f#"$ROOT"/} missing '$lit'; "
    done
    $GREP -qF 'No Critical or High finding is considered fixed without a corresponding test change' "$f" \
        && t6_bad="${t6_bad}${f#"$ROOT"/} still carries the old absolute test mandate; "
done

who_writes=$($GREP -m1 -F '**Who writes it:**' "$SRC_RT")
printf '%s' "$who_writes" | $GREP -qF 'append an entry for any defect that reproduced' \
    || t6_bad="${t6_bad}Who writes it does not name the loops as writers of a reproduced-defect entry; "
printf '%s' "$who_writes" | $GREP -qF 'self-service `out-of-scope`' \
    || t6_bad="${t6_bad}Who writes it does not admit a self-service out-of-scope; "
# F4: a rewrite naming only one loop as the roster's justification still passed — require both.
printf '%s' "$who_writes" | $GREP -qF '/review-code-fix-loop' || t6_bad="${t6_bad}Who writes it does not name /review-code-fix-loop; "
printf '%s' "$who_writes" | $GREP -qF '/review-iterate' || t6_bad="${t6_bad}Who writes it does not name /review-iterate; "

still_open_files=$($GREP -rl "STILL OPEN" "${T1_ROOTS[@]}" 2>/dev/null | sed "s#^$ROOT/##" | sort -u)
[ "$still_open_files" = "platforms/claude/commands/review-iterate.md" ] \
    || t6_bad="${t6_bad}STILL OPEN occurs in: $(printf '%s' "$still_open_files" | tr '\n' ' '), want only review-iterate.md; "
span_2b=$(awk '/\*\*2b\. Apply the fix:\*\*/{f=1;next} f && /\*\*2c\. Scoped verification\*\*/{exit} f' "$REVITER")
# F6: renaming the 2b anchor silently empties span_2b, and an empty span trivially contains no
# "STILL OPEN" — the only negative check behind it vanishes with no failure to show for it. Guard
# non-emptiness before trusting the absence.
[ -n "$span_2b" ] || t6_bad="${t6_bad}span_2b extraction is empty — the '**2b. Apply the fix:**' anchor may have been renamed; "
printf '%s' "$span_2b" | $GREP -q "STILL OPEN" && t6_bad="${t6_bad}STILL OPEN appears inside the 2b span; "

# H1: the old exit anchor ('### Step 3') let Step 2d's 34 lines sit inside span_2c, so a pin
# added below could be satisfied by text relocated into 2d instead of staying in 2c proper. Exit
# at 2d instead, and guard non-emptiness the same way span_2b does (F6) — an empty span from a
# renamed anchor would otherwise vacuous-pass every check below it.
span_2c=$(awk '/\*\*2c\. Scoped verification\*\*/{f=1} f && /\*\*2d\. Record result\*\*/{exit} f' "$REVITER")
[ -n "$span_2c" ] || t6_bad="${t6_bad}span_2c extraction is empty — the '**2c. Scoped verification**' or '**2d. Record result**' anchor may have been renamed; "
printf '%s\n' "$span_2c" | $GREP -qF 'For Critical and High' || t6_bad="${t6_bad}Step 2c missing 'For Critical and High'; "
printf '%s\n' "$span_2c" | $GREP -qF 'in addition to verifying the fix resolves the finding' || t6_bad="${t6_bad}Step 2c missing 'in addition to verifying the fix resolves the finding'; "
printf '%s\n' "$span_2c" | $GREP -qF "coder's fix response" || t6_bad="${t6_bad}Step 2c does not pass the coder's fix response to its verifier; "
# H1: round 1's exact defect — restoring "Return STILL OPEN in every other case." verbatim —
# left the suite green because nothing pinned the scoped replacement sentence and nothing forbade
# the phrase it replaced.
printf '%s\n' "$span_2c" | $GREP -qF "when the finding's concern survives, or when none of the three is present" \
    || t6_bad="${t6_bad}Step 2c missing the scoped STILL OPEN condition ('when the finding's concern survives, or when none of the three is present'); "
printf '%s\n' "$span_2c" | $GREP -q "in every other case" \
    && t6_bad="${t6_bad}Step 2c still carries the unscoped 'in every other case' STILL OPEN condition; "

# H1/M1: the batch loop's Step 3 fix-response paragraph was pinned by nothing — deleting it, or
# restoring the pre-fix referent wording, reverted green. Scope to its own span so a rename
# elsewhere in the file cannot stand in for it.
cfl_step3=$(awk '/^### Step 3: Re-review/{f=1;next} f && /^### /{exit} f' "$CLAUDE/commands/review-code-fix-loop.md")
[ -n "$cfl_step3" ] || t6_bad="${t6_bad}review-code-fix-loop.md Step 3 extraction is empty — the '### Step 3: Re-review' anchor may have been renamed; "
printf '%s\n' "$cfl_step3" | $GREP -qF "coder's fix response" || t6_bad="${t6_bad}review-code-fix-loop.md Step 3 does not pass the coder's fix response to the re-review; "
printf '%s\n' "$cfl_step3" | $GREP -qF "record the accepted" || t6_bad="${t6_bad}review-code-fix-loop.md Step 3 does not record the accepted discharge on the finding's resolution line; "

# H5: review-iterate.md's Step 3 final re-review had the same gap at its twin site — no
# fix-response pass-through and no accepted-discharge record, so a finding discharged at 2c
# re-presented at the final gate as a test-less fix.
step3_final=$(awk '/^### Step 3: Final full re-review/{f=1;next} f && /^### /{exit} f' "$REVITER")
[ -n "$step3_final" ] || t6_bad="${t6_bad}review-iterate.md Step 3 (final re-review) extraction is empty — the '### Step 3: Final full re-review' anchor may have been renamed; "
printf '%s\n' "$step3_final" | $GREP -qF "fix responses collected in Step 2" || t6_bad="${t6_bad}review-iterate.md Step 3 does not pass the per-finding fix responses to the final re-review; "
printf '%s\n' "$step3_final" | $GREP -qF "record the accepted" || t6_bad="${t6_bad}review-iterate.md Step 3 does not record the accepted discharge on the finding's resolution line; "

if [ -z "$t6_bad" ]; then
    pass "the ordered check, the per-site discharge wording, the roster rewrite, and STILL OPEN's sole scoped home in review-iterate.md all hold"
else
    fail "the ordered check, the per-site discharge wording, the roster rewrite, and STILL OPEN's sole scoped home in review-iterate.md all hold" "$t6_bad"
fi

echo "== T7: the §3-admission rule (mechanism-proportionality step 6) reaches all three sites, each inside its own span, byte-identical on the shared domain clause, pinned by one anchor phrase =="

# T7: design.md §5 ships the same rule as three independently-authored lines — the source
# paragraph in architecture/SKILL.md, the template note in DESIGN-TEMPLATE.md, and the review
# flag in review-design.md — so nothing but an assertion binding all three together catches one
# of them drifting, being deleted, or being relocated out of the span that scopes it. Deliberately
# reuses T1_ROOTS (both config roots) for the absence half below rather than declaring a fresh
# root pair — same corpus, same guard, and this comment is the record of that reuse.
#
# Placed after the T6 block for numeric reading order (T1..T6, then T7) — still after the T1
# block itself, since T1_ROOTS must already be in scope. Moved above T1, `${#T1_ROOTS[@]}`
# on an unset array raises an unbound-variable error under `set -u` (element expansion
# `"${T1_ROOTS[@]}"` alone does not, in bash 4.4+). Left unguarded, that error abandons the
# compound command it sits in, leaves `n_t7_scanned` unset, and the later pass-line
# interpolation of that variable aborts the whole suite at exit 1 — losing every remaining
# assertion and printing no summary. The existence guard below, tested before any length or
# element expansion, converts that mid-suite abort into a single named FAIL while letting the
# suite run to completion.
t7_bad=""
if [ "${T1_ROOTS+set}" = set ]; then
    [ "${#T1_ROOTS[@]}" -eq 2 ] || t7_bad="${t7_bad}T1_ROOTS has ${#T1_ROOTS[@]} element(s), want 2; "
    for r in "${T1_ROOTS[@]}"; do
        [ -d "$r" ] || t7_bad="${t7_bad}root '$r' is not a directory — the absence-half scan would run over nothing; "
    done
    # F5-style positive control (see T1 above): an absence-only scan below has no positive
    # control of its own, so confirm the scan actually walks a non-zero file count first.
    n_t7_scanned=$(find "${T1_ROOTS[@]}" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    [ "$n_t7_scanned" -gt 0 ] || t7_bad="${t7_bad}0 Markdown files found under the config roots — the absence-half scan ran over nothing; "

    T7_ANCHOR="a failure mode of the environment"
    # CM1: the two endpoint tokens of the shared domain clause used to be the only thing pinned
    # (via t7_common below) — each occurring somewhere on the line, in any order, with anything
    # between them. A meaning-inverting or scope-narrowing edit to the prose between the tokens
    # left both green. Extract the whole clause between them and compare it byte-for-byte across
    # sites instead of trusting the endpoints alone.
    T7_DOMAIN_START="It covers Functional Requirement"
    T7_DOMAIN_END="limitation of the environment"
    REVIEW_DESIGN_DOC="$CLAUDE/commands/review-design.md"

    # Reuses ARCH_CLASS and DESIGN_TEMPLATE, already declared above for the class-label and
    # doc-metrics checks, rather than redeclaring the same two paths under new names.
    t7_files=("$ARCH_CLASS" "$DESIGN_TEMPLATE" "$REVIEW_DESIGN_DOC")
    t7_starts=(
        "### What each class demands"
        "## 3. Implementation Context"
        "**Flag (design-level concerns):**"
    )
    t7_ends=(
        "### Choosing between them"
        "## 4. Architecture Overview"
        "**Ticket Constraint Guardrail"
    )
    # Both domain-clause halves (scope, then carve-out), the two class literals the rule is
    # scoped to, the tag under test, and the escape route — every one of the three lines carries
    # all six, on the same line as the anchor phrase.
    t7_common=(
        '`CI`' '`TEST`' '`analysis`' '## 8. Open Questions'
        'Constraint bullets alike' 'limitation of the environment'
    )
    t7_domain_clauses=()

    for i in "${!t7_files[@]}"; do
        f="${t7_files[$i]}"
        start="${t7_starts[$i]}"
        end="${t7_ends[$i]}"
        name="${f#"$ROOT"/}"

        if [ ! -f "$f" ]; then
            t7_bad="${t7_bad}$name: file does not resolve; "
            continue
        fi
        $GREP -qF "$start" "$f" || { t7_bad="${t7_bad}$name: span start '$start' not found; "; continue; }
        # CM2: existence alone doesn't prove order. A terminator hoisted above the span start (or
        # renamed away) leaves the awk range below with no closing match once `s` has been seen,
        # so the range silently runs to EOF — the exact widening this guard exists to catch.
        # Probe with the extraction's own index()-after-index() semantics rather than a bare grep.
        awk -v s="$start" -v e="$end" 'index($0,s){f=1; next} f && index($0,e){found=1; exit} END{exit !found}' "$f" \
            || { t7_bad="${t7_bad}$name: span terminator '$end' not found after '$start' — the span would silently widen to EOF; "; continue; }

        t7_span=$(awk -v s="$start" -v e="$end" 'index($0,s){f=1} f && index($0,e){exit} f' "$f")

        # Occurrences, not lines: `grep -cF` reads 1 for a second copy appended to the rule's own
        # line, because it counts matching lines, not matches — this corpus bans manual line
        # wrapping, so the whole rule is one line and a same-line decoy must still redden.
        whole_count=$($GREP -oiF "$T7_ANCHOR" "$f" | wc -l | tr -d ' ')
        [ "$whole_count" -eq 1 ] || t7_bad="${t7_bad}$name: anchor phrase occurs $whole_count time(s) in the whole file, want exactly 1; "

        span_count=$(printf '%s\n' "$t7_span" | $GREP -oiF "$T7_ANCHOR" | wc -l | tr -d ' ')
        if [ "$span_count" -ne 1 ]; then
            # CM4: a gutted or absent rule line makes every literal check below vacuous — one
            # deleted sentence used to fan out into 8 derived failures stacked on the 2 real ones.
            t7_bad="${t7_bad}$name: anchor phrase occurs $span_count time(s) inside its own span ('$start' .. '$end'), want exactly 1 — deleted, relocated out of span, or a second copy; "
            continue
        fi

        rule_line=$(printf '%s\n' "$t7_span" | $GREP -F "$T7_ANCHOR")
        for lit in "${t7_common[@]}"; do
            printf '%s' "$rule_line" | $GREP -qF "$lit" || t7_bad="${t7_bad}$name: rule line missing '$lit'; "
        done
        printf '%s' "$rule_line" | $GREP -q 'PRODUCT' && t7_bad="${t7_bad}$name: rule line names 'PRODUCT' — FR-3 keeps this rule off both high classes; "

        if [ "$f" = "$REVIEW_DESIGN_DOC" ]; then
            printf '%s' "$rule_line" | $GREP -qF 'flag as Medium' || t7_bad="${t7_bad}$name: rule line missing 'flag as Medium'; "
        else
            printf '%s' "$rule_line" | $GREP -qF '## Clarifications' || t7_bad="${t7_bad}$name: rule line missing '## Clarifications'; "
            printf '%s' "$rule_line" | $GREP -qF '`decision <date>`' || t7_bad="${t7_bad}$name: rule line missing '\`decision <date>\`'; "
        fi

        # Fixed-string extraction, matching CM2's index()-after-index() discipline above: sed's
        # interpolated `${T7_DOMAIN_START}.*${T7_DOMAIN_END}` (a) aborts on stderr if either anchor
        # ever carries a regex metacharacter, leaving t7_domain_clauses empty and every `[ -n ... ]`
        # comparison below silently skipped while the pass banner still claims byte-identity; and
        # (b) is regex-greedy, so a drifted clause plus a pristine copy appended on the same line
        # extracts the trailing (last) copy instead of catching the drift. index()/substr() takes
        # the first start token, then the first end token after it, with no regex involved.
        domain_clause=$(printf '%s' "$rule_line" | awk -v s="$T7_DOMAIN_START" -v e="$T7_DOMAIN_END" '
            {
                si = index($0, s)
                if (si == 0) { exit }
                rest = substr($0, si)
                ei = index(rest, e)
                if (ei == 0) { exit }
                print substr(rest, 1, ei + length(e) - 1)
            }')
        if [ -n "$domain_clause" ]; then
            t7_domain_clauses[$i]="$domain_clause"
        else
            t7_bad="${t7_bad}$name: domain clause anchors ('$T7_DOMAIN_START' .. '$T7_DOMAIN_END') not found on the rule line — cannot compare for byte-identity; "
        fi
    done

    # CM1: compare the extracted clause pairwise against the first site's, only when both sides
    # actually extracted one — a site that already failed above (and already carries its own
    # message) shouldn't also report a spurious mismatch against an empty placeholder. Iterate
    # every site index, not a hardcoded pair, so a future fourth site added to t7_files is
    # compared too; index 0 against itself is a trivial no-op equality.
    for i in "${!t7_files[@]}"; do
        if [ -n "${t7_domain_clauses[0]:-}" ] && [ -n "${t7_domain_clauses[$i]:-}" ] \
            && [ "${t7_domain_clauses[$i]}" != "${t7_domain_clauses[0]}" ]; then
            t7_bad="${t7_bad}${t7_files[$i]#"$ROOT"/}: shared domain clause differs from ${t7_files[0]#"$ROOT"/} — not byte-identical; "
        fi
    done

    # Absence half: the anchor phrase must resolve to exactly these three files under both config
    # roots. A fourth uncontrolled copy in a fourth file is invisible to the per-site loop above,
    # which only ever looks at the three named files — this is the only half that catches it.
    # `-i`, matching T1's sibling scan above: a sentence-initial capitalised fourth copy is
    # otherwise invisible to a case-sensitive `-F` match.
    anchor_files=$($GREP -rliF "$T7_ANCHOR" "${T1_ROOTS[@]}" 2>/dev/null | sort -u)
    expected_files=$(printf '%s\n' "${t7_files[@]}" | sort -u)
    [ "$anchor_files" = "$expected_files" ] \
        || t7_bad="${t7_bad}anchor phrase resolves outside the three named sites — found: $(printf '%s' "$anchor_files" | tr '\n' ' '); "
else
    t7_bad="T1_ROOTS is unset — T7 must run after the T1 block, which declares it; "
fi

if [ -z "$t7_bad" ]; then
    pass "the §3-admission rule reaches all three sites inside their own spans, each carries the shared domain clause byte-identically and no 'PRODUCT' literal, and the anchor phrase resolves to exactly these three files across $n_t7_scanned Markdown file(s) under the config roots"
else
    fail "the §3-admission rule reaches all three sites inside their own spans, each carries the shared domain clause byte-identically and no 'PRODUCT' literal, and the anchor phrase resolves to exactly these three files under the config roots" "$t7_bad"
fi

# === The comment gate (mechanism-proportionality step 7) ====================================
#
# design.md §5 ships the comment-ratio gate across five prose sites: four spans of
# commands/verify.md (the tier-1 linter-discovery sub-item, the tier-3a step-9 run site, the
# Requirements bullet, and the Failure Handling recovery item) plus one span of
# agents/coder.md (the Comments-list rule and its ticket-reference qualification). T-a binds
# the four verify.md spans together; T-b binds the coder.md span and absence-checks it against
# a second copy under either config root, the same two roots T1/T7 already declare. S3 above is also
# edited in place for this step: it now re-terminates at the next numbered step instead of the
# next `## ` heading, since step 9 sits between step 8 and that heading, and it pins the new
# `BASE=` assignment plus the absence of a leaked comment-gate.sh reference.

echo "== T-a: /verify's four comment-gate spans carry their pinned literals, each inside its own span (mechanism-proportionality step 7) =="

# T-a: each span is read with `awk '/opener/{f=1;next} f&&/terminator/{exit} f'` — the `next` is
# what stops a numbered-step opener from matching a numbered-step terminator and exiting on its
# own first line. Occurrences, not lines, throughout: this corpus bans manual line wrapping, so
# a whole rule is often one line and a same-line decoy must still redden.
ta_bad=""

# Linter Discovery span: '**Linter Discovery Process:**' -> '**Language-Specific Linters:**'.
# Anchored on the no-configuration clause, which is unique to the one sub-item step 7 adds —
# a deleted or relocated sub-item drops the anchor from the span entirely.
ld_span=$(awk '/\*\*Linter Discovery Process:\*\*/{f=1;next} f&&/\*\*Language-Specific Linters:\*\*/{exit} f' "$VERIFY_DOC")
if [ -z "$ld_span" ]; then
    ta_bad="${ta_bad}Linter Discovery span not found; "
else
    ld_anchor='ships no linter configuration into the repo under verification'
    n_ld_anchor=$(printf '%s\n' "$ld_span" | $GREP -oiF "$ld_anchor" | wc -l | tr -d ' ')
    if [ "$n_ld_anchor" -ne 1 ]; then
        ta_bad="${ta_bad}Linter Discovery span: no-configuration clause occurs $n_ld_anchor time(s), want exactly 1; "
    else
        ld_line=$(printf '%s\n' "$ld_span" | $GREP -F "$ld_anchor")
        for lit in 'ERA001' 'revive' 'missing_docs'; do
            printf '%s' "$ld_line" | $GREP -qF "$lit" || ta_bad="${ta_bad}Linter Discovery sub-item missing '$lit'; "
        done
    fi
fi

# Step-9 span: '9. **Comment ratio' -> the next numbered step or the next '## ', whichever first.
step9_span=$(awk '/^9\. \*\*Comment ratio/{f=1;next} f&&(/^[0-9]+\. /||/^## /){exit} f' "$VERIFY_DOC")
step9_opener=$($GREP -n '^9\. \*\*Comment ratio' "$VERIFY_DOC" | head -1 | cut -d: -f1)
step8_opener=$($GREP -n '^8\. \*\*Attribution' "$VERIFY_DOC" | head -1 | cut -d: -f1)
if [ -z "$step9_span" ]; then
    ta_bad="${ta_bad}step-9 span not found; "
else
    n_invoke=$(printf '%s\n' "$step9_span" | $GREP -oiF 'comment-gate.sh' | wc -l | tr -d ' ')
    [ "$n_invoke" -eq 1 ] || ta_bad="${ta_bad}step-9 span: comment-gate.sh invocation occurs $n_invoke time(s), want exactly 1; "

    printf '%s\n' "$step9_span" | $GREP -qF 'BASE=$(git symbolic-ref' \
        || ta_bad="${ta_bad}step-9 span missing the 'BASE=\$(git symbolic-ref' assignment — a bare resolution line with no BASE= in front satisfies a looser pin; "
    printf '%s\n' "$step9_span" | $GREP -qF 'git remote show origin' \
        || ta_bad="${ta_bad}step-9 span missing the 'git remote show origin' fallback half of the assignment; "
    printf '%s\n' "$step9_span" | $GREP -qF '${BASE:?' \
        || ta_bad="${ta_bad}step-9 span missing the '\${BASE:?' guard — a hardcoded base branch would drop this; "
    printf '%s\n' "$step9_span" | $GREP -qF 'Exit `0` means the scan ran' \
        || ta_bad="${ta_bad}step-9 span missing the exit-contract phrase 'Exit \`0\` means the scan ran' — its absence lets a caller wire &&; "

    warn_line=$(printf '%s\n' "$step9_span" | $GREP -F 'and do not stop the run')
    if [ -z "$warn_line" ]; then
        ta_bad="${ta_bad}step-9 span missing 'and do not stop the run'; "
    else
        printf '%s' "$warn_line" | $GREP -qF '`BLOCK` and any flag — a bare suppression, an unreferenced `TODO`, an over-long comment run, a planning reference — is a failure' \
            || ta_bad="${ta_bad}the same sentence does not carry the \`BLOCK\`-and-any-flag failure clause — a WARN/BLOCK swap between the two verdict sentences keeps every literal in isolation but separates this pair; "

        # The pairing above catches a literal two-way swap but not a one-sided rewrite —
        # changing only the first verdict word keeps both pinned literals in place while
        # inverting which verdict the sentence says does not stop the run. Isolate the
        # non-stopping sentence itself (line start to its own period) and require it to name
        # `WARN`, not `BLOCK`.
        stopping_sentence=$(printf '%s' "$warn_line" | $GREP -oE '^[[:space:]]*[^.]*and do not stop the run\.')
        if [ -z "$stopping_sentence" ]; then
            ta_bad="${ta_bad}could not isolate the non-stopping sentence ending in 'and do not stop the run.'; "
        elif printf '%s' "$stopping_sentence" | $GREP -qF '`BLOCK`'; then
            ta_bad="${ta_bad}the non-stopping sentence names \`BLOCK\` — a one-sided verdict-word rewrite; "
        elif ! printf '%s' "$stopping_sentence" | $GREP -qF '`WARN`'; then
            ta_bad="${ta_bad}the non-stopping sentence does not name \`WARN\`; "
        fi
    fi

    if [ -n "$step9_opener" ] && [ -n "$step8_opener" ]; then
        [ "$step9_opener" -gt "$step8_opener" ] \
            || ta_bad="${ta_bad}step-9 opener (line $step9_opener) is not after step-8 opener (line $step8_opener); "
    else
        ta_bad="${ta_bad}could not locate the step-8 or step-9 opener line number; "
    fi

    # The invocation names ~/.claude/scripts/comment-gate.sh (the installed location); resolve
    # that filename under platforms/claude/scripts/ (the shipped location) instead of asserting
    # the installed path literally, which the test tree never populates.
    invoked=$(printf '%s\n' "$step9_span" | $GREP -oE '[^[:space:]]*comment-gate\.sh' | head -1)
    if [ -z "$invoked" ]; then
        ta_bad="${ta_bad}step-9 span: could not extract the invoked script path; "
    else
        resolved="$CLAUDE/scripts/$(basename "$invoked")"
        [ -f "$resolved" ] \
            || ta_bad="${ta_bad}invoked path '$invoked' does not resolve under platforms/claude/scripts/ (looked for $resolved) — a rename on one side without the other is otherwise invisible; "
    fi
fi

# '## Requirements' span: '## Requirements' -> '## Failure Handling'.
req_span=$(awk '/^## Requirements/{f=1;next} f&&/^## Failure Handling/{exit} f' "$VERIFY_DOC")
if [ -z "$req_span" ]; then
    ta_bad="${ta_bad}## Requirements span not found; "
else
    n_req=$(printf '%s\n' "$req_span" | $GREP -oiF 'Comment ratio run over every changed file' | wc -l | tr -d ' ')
    if [ "$n_req" -ne 1 ]; then
        ta_bad="${ta_bad}## Requirements span: 'Comment ratio run over every changed file' occurs $n_req time(s), want exactly 1; "
    else
        # The escape clause is the requirement's only path to "all checks pass" when the
        # gate flags a genuine false positive — without it the bullet is unconditionally
        # unsatisfiable on any run that hits one.
        req_line=$(printf '%s\n' "$req_span" | $GREP -F 'Comment ratio run over every changed file')
        printf '%s' "$req_line" | $GREP -qF "or each is reported as a pre-authorized false positive — satisfied by the stop-for-the-user's-decision handoff in Failure Handling item 8" \
            || ta_bad="${ta_bad}## Requirements bullet missing the pre-authorized-false-positive escape clause; "
    fi
fi

# '## Failure Handling' span: '## Failure Handling' -> '## Execution Order is Critical'.
fh_span=$(awk '/^## Failure Handling/{f=1;next} f&&/^## Execution Order is Critical/{exit} f' "$VERIFY_DOC")
if [ -z "$fh_span" ]; then
    ta_bad="${ta_bad}## Failure Handling span not found; "
else
    n_fh_block=$(printf '%s\n' "$fh_span" | $GREP -oiF '`BLOCK`' | wc -l | tr -d ' ')
    if [ "$n_fh_block" -ne 1 ]; then
        ta_bad="${ta_bad}## Failure Handling span: '\`BLOCK\`' occurs $n_fh_block time(s), want exactly 1; "
    else
        fh_line=$(printf '%s\n' "$fh_span" | $GREP -F '`BLOCK`')
        # The stop-for-the-user's-decision clause is what the Requirements escape clause
        # above points at by name ("Failure Handling item 8") — dropping it here breaks that
        # pointer even if the Requirements literal itself survives.
        for lit in 'delete the body comments the code does not need' \
                   'give a bare suppression marker its reason' \
                   'do not edit the constants' \
                   "report it and stop for the user's decision"; do
            printf '%s' "$fh_line" | $GREP -qF "$lit" || ta_bad="${ta_bad}## Failure Handling item missing '$lit'; "
        done
    fi
fi

if [ -z "$ta_bad" ]; then
    pass "/verify's four comment-gate spans (linter discovery, step 9, Requirements, Failure Handling) each carry their pinned literals"
else
    fail "/verify's four comment-gate spans (linter discovery, step 9, Requirements, Failure Handling) each carry their pinned literals" "$ta_bad"
fi

echo "== T-b: agents/coder.md's Comments span carries the body-comment rule and the TODOs ticket qualification, with no second copy under either config root (mechanism-proportionality step 7) =="

# T-b: `### Comments` -> `### Linter Suppressions`, the section that follows it and carries
# adjacent flag vocabulary a loose whole-file match would otherwise accept. Occurrences, not
# lines, throughout. Reuses T1_ROOTS (already declared and directory-checked by the T1 block
# above, which this section runs after) rather than declaring a fresh root pair.
CODER_DOC="$CLAUDE/agents/coder.md"
tb_bad=""
# Declared unconditionally, not inside the span-found branch below — the absence-half scan
# further down needs it regardless of whether the span itself resolved, and referencing an
# unset variable under `set -u` would abort the whole suite rather than failing this one block.
rule_lit='Body comments are for the genuinely unusual.'
if [ "${T1_ROOTS+set}" != set ]; then
    tb_bad="T1_ROOTS is unset — T-b must run after the T1 block, which declares it; "
else
    comments_span=$(awk '/^### Comments/{f=1;next} f&&/^### Linter Suppressions/{exit} f' "$CODER_DOC")
    if [ -z "$comments_span" ]; then
        tb_bad="${tb_bad}### Comments span not found; "
    else
        n_rule=$(printf '%s\n' "$comments_span" | $GREP -oiF "$rule_lit" | wc -l | tr -d ' ')
        if [ "$n_rule" -ne 1 ]; then
            tb_bad="${tb_bad}body-comment rule occurs $n_rule time(s) in the Comments span, want exactly 1; "
        else
            rule_line=$(printf '%s\n' "$comments_span" | $GREP -F "$rule_lit")
            printf '%s' "$rule_line" | $GREP -qF 'body-comment lines against added code lines' \
                || tb_bad="${tb_bad}rule line missing 'body-comment lines against added code lines'; "
        fi

        n_todo=$(printf '%s\n' "$comments_span" | $GREP -oiF 'TODOs carrying a ticket reference' | wc -l | tr -d ' ')
        [ "$n_todo" -eq 1 ] || tb_bad="${tb_bad}'TODOs carrying a ticket reference' occurs $n_todo time(s) in the Comments span, want exactly 1; "
    fi

    # Absence half: the rule occurs in this one file and nowhere else under either config root —
    # mirrors T7's own absence-half pattern over the same T1_ROOTS pair, run unconditionally
    # (like T7's) rather than gated on the span checks above, with `2>/dev/null` covering a
    # non-directory root the loop below already flags.
    for r in "${T1_ROOTS[@]}"; do
        [ -d "$r" ] || tb_bad="${tb_bad}root '$r' is not a directory — the absence-half scan would run over nothing; "
    done
    rule_files=$($GREP -rliF "$rule_lit" "${T1_ROOTS[@]}" 2>/dev/null | sort -u)
    [ "$rule_files" = "$CODER_DOC" ] \
        || tb_bad="${tb_bad}body-comment rule found outside agents/coder.md: $(printf '%s' "$rule_files" | tr '\n' ' '); "
fi

if [ -z "$tb_bad" ]; then
    pass "agents/coder.md's Comments span carries the body-comment rule and the TODOs ticket qualification, with no second copy under either config root"
else
    fail "agents/coder.md's Comments span carries the body-comment rule and the TODOs ticket qualification, with no second copy under either config root" "$tb_bad"
fi

echo "== Command files: research.md and review-mr.md's shared Prior Context contract =="

# Seven assertions over the prose of two public command files. A missing anchor is a real
# content regression — the requirement text moved, was renamed, or was deleted — so each
# extraction's own failure becomes that row's failure message rather than a separate one.
RESEARCH_MD="$CLAUDE/commands/research.md"
REVIEW_MR_MD="$CLAUDE/commands/review-mr.md"

research_raw=$(extract-section "$RESEARCH_MD" "## Output" 2>&1)
research_status=$?
research_output=""
research_error=""
if [ "$research_status" -eq 0 ]; then research_output="$research_raw"; else research_error="$research_raw"; fi

step2b_raw=$(extract-section "$REVIEW_MR_MD" "### Step 2b" 2>&1)
step2b_status=$?
step2b_output=""
step2b_error=""
if [ "$step2b_status" -eq 0 ]; then step2b_output="$step2b_raw"; else step2b_error="$step2b_raw"; fi

step3b_raw=$(extract-section "$REVIEW_MR_MD" "### Step 3b" 2>&1)
step3b_status=$?
step3b_output=""
step3b_error=""
if [ "$step3b_status" -eq 0 ]; then step3b_output="$step3b_raw"; else step3b_error="$step3b_raw"; fi

prior_rows_value() {   # $1: extracted section text — the first integer following PRIOR_CONTEXT_ROWS
    printf '%s' "$1" | $GREP -oE 'PRIOR_CONTEXT_ROWS[^0-9]{1,20}[0-9]+' | $GREP -oE '[0-9]+$' | head -1
}

# Rows 1-6 branch on the captured exit status, not on emptiness: `extract-section` exits 0
# with an empty body for a real-but-empty section, and that case is not the same failure as
# a missing anchor — collapsing them under `[ -z "$output" ]` reported "extraction failed:"
# with a blank reason either way.
#
# Rows 1, 2, and 4 also bind their required tokens to one sentence rather than to the whole
# extracted section: a rewrite that keeps every required token but reverses what the
# sentence says (e.g. "paste the whole run, and drop nothing") previously stayed green,
# because co-occurrence anywhere in the section is not the same claim as one sentence making
# it. Each bound sentence is pulled out with its own `**Lead-in:**` marker in the command
# file and extracted here with `[^.]*\.`, which cannot cross the period into a neighboring
# sentence — so a token that legitimately recurs elsewhere in the same paragraph (row 4's
# "epic", row 1's "never") does not leak into the check.

# Row 1: a silently truncated slice reading as full coverage is the exact property §1 of
# the design faults the old digest for losing.
if [ "$research_status" -ne 0 ]; then
    fail "research.md's ## Output states the 'N of M shown' disclosure" "extraction failed (exit $research_status): $research_error"
elif [ -z "$research_output" ]; then
    fail "research.md's ## Output states the 'N of M shown' disclosure" "anchor found, section body is empty"
else
    third_line=$(printf '%s' "$research_output" | $GREP -oE '\*\*Third line:\*\*[^.]*\.' | head -1)
    if [ -z "$third_line" ]; then
        fail "research.md's ## Output states the 'N of M shown' disclosure" \
             "no '**Third line:**' sentence found in the extracted section"
    elif printf '%s' "$third_line" | $GREP -qF 'N of M shown' \
         && ! printf '%s' "$third_line" | $GREP -qiE 'is gone|no longer|retired|was '; then
        pass "research.md's ## Output states the 'N of M shown' disclosure"
    else
        fail "research.md's ## Output states the 'N of M shown' disclosure" "sentence: $third_line"
    fi
fi

# Row 2: pasting either producer heading closes the section early and everything after it
# escapes doc-metrics's skip — measured at four sections and ~816 words (design §5.2).
if [ "$research_status" -ne 0 ]; then
    fail "research.md's ## Output names ## Roadmap and ## Prior decisions as dropped" "extraction failed (exit $research_status): $research_error"
elif [ -z "$research_output" ]; then
    fail "research.md's ## Output names ## Roadmap and ## Prior decisions as dropped" "anchor found, section body is empty"
else
    dropped_sentence=$(printf '%s' "$research_output" | $GREP -oE '\*\*Dropped:\*\*[^.]*\.' | head -1)
    if [ -z "$dropped_sentence" ]; then
        fail "research.md's ## Output names ## Roadmap and ## Prior decisions as dropped" \
             "no '**Dropped:**' sentence found in the extracted section"
    elif printf '%s' "$dropped_sentence" | $GREP -qF '## Roadmap' \
         && printf '%s' "$dropped_sentence" | $GREP -qF '## Prior decisions' \
         && printf '%s' "$dropped_sentence" | $GREP -qiE '\bdropped\b' \
         && ! printf '%s' "$dropped_sentence" | $GREP -qiE '\b(not|never|nothing|no longer)\b'; then
        pass "research.md's ## Output names ## Roadmap and ## Prior decisions as dropped"
    else
        fail "research.md's ## Output names ## Roadmap and ## Prior decisions as dropped" "sentence: $dropped_sentence"
    fi
fi

# Row 3: without the shape gate, a projctl installed before this change returns the old
# digest at exit 0, and pasting it whole is the same escape as row 2 by a different route.
if [ "$research_status" -ne 0 ]; then
    fail "research.md's ## Output gates reduction on the five-column header row" "extraction failed (exit $research_status): $research_error"
elif [ -z "$research_output" ]; then
    fail "research.md's ## Output gates reduction on the five-column header row" "anchor found, section body is empty"
else
    gate_sentence=$(printf '%s' "$research_output" | $GREP -oE '\*\*Gate:\*\*[^.]*\.' | head -1)
    if [ -z "$gate_sentence" ]; then
        fail "research.md's ## Output gates reduction on the five-column header row" \
             "no '**Gate:**' sentence found in the extracted section"
    else
        missing_cols=""
        for col in score tier repo path heading; do
            printf '%s' "$gate_sentence" | $GREP -qF "\`$col\`" || missing_cols="$missing_cols $col"
        done
        # "only when" is the conditional itself, not just the word "gate" (which the lead-in
        # marker would otherwise supply for free) — a descriptive rewrite that drops the
        # gate keeps the column list and "header row" but has nothing to put here.
        if [ -z "$missing_cols" ] && printf '%s' "$gate_sentence" | $GREP -qi 'header row' \
           && printf '%s' "$gate_sentence" | $GREP -qF 'only when'; then
            pass "research.md's ## Output gates reduction on the five-column header row"
        else
            fail "research.md's ## Output gates reduction on the five-column header row" \
                 "missing column token(s):$missing_cols; or no 'header row'/'only when' phrase; sentence: $gate_sentence"
        fi
    fi
fi

# Row 4: the ticket body silently re-dropped is the defect this whole change exists to fix.
if [ "$step2b_status" -ne 0 ]; then
    fail "review-mr.md's ### Step 2b retains the ticket description verbatim" "extraction failed (exit $step2b_status): $step2b_error"
elif [ -z "$step2b_output" ]; then
    fail "review-mr.md's ### Step 2b retains the ticket description verbatim" "anchor found, section body is empty"
else
    retain_sentence=$(printf '%s' "$step2b_output" | $GREP -oE '\*\*Retained verbatim:\*\*[^.]*\.' | head -1)
    if [ -z "$retain_sentence" ]; then
        fail "review-mr.md's ### Step 2b retains the ticket description verbatim" \
             "no '**Retained verbatim:**' sentence found in the Step 2b section"
    elif printf '%s' "$retain_sentence" | $GREP -qiF "issue's description" \
         && printf '%s' "$retain_sentence" | $GREP -qi 'verbatim' \
         && ! printf '%s' "$retain_sentence" | $GREP -qiF 'epic'; then
        pass "review-mr.md's ### Step 2b retains the ticket description verbatim"
    else
        fail "review-mr.md's ### Step 2b retains the ticket description verbatim" "sentence: $retain_sentence"
    fi
fi

# Row 5: Codex runs with --ignore-user-config --ignore-rules, so the bundled review-request
# document is the only way the table reaches it — losing this silently drops the table for
# that reviewer alone, with nothing else in the suite able to notice. Requires a positive
# verb ("lands in" / "paste") on the same line as both tokens, not just their co-occurrence
# — "review-request" and "## Context" both survive a flip to "Do not copy ... into the
# review-request's ## Context section", so the verb and a bounded negation guard carry the
# check instead of the two nouns alone.
if [ "$step3b_status" -ne 0 ]; then
    fail "review-mr.md's ### Step 3b routes the table into the review-request's ## Context section" \
         "extraction failed (exit $step3b_status): $step3b_error"
elif [ -z "$step3b_output" ]; then
    fail "review-mr.md's ### Step 3b routes the table into the review-request's ## Context section" \
         "anchor found, section body is empty"
else
    context_line=$(printf '%s\n' "$step3b_output" | $GREP -F 'review-request' | $GREP -F '## Context')
    apos="'"
    neg_pattern="(do not|don${apos}t|never)[^.]*(land|paste|copy)"
    if [ -z "$context_line" ]; then
        fail "review-mr.md's ### Step 3b routes the table into the review-request's ## Context section" \
             "no single line names both 'review-request' and '## Context'"
    elif printf '%s' "$context_line" | $GREP -qiE 'lands in|paste' \
         && ! printf '%s' "$context_line" | $GREP -qiE "$neg_pattern"; then
        pass "review-mr.md's ### Step 3b routes the table into the review-request's ## Context section"
    else
        fail "review-mr.md's ### Step 3b routes the table into the review-request's ## Context section" \
             "line lacks a positive verb (lands in / paste), or a negation survives: $context_line"
    fi
fi

# Row 6: a repo-specific path in a public command file. The pre-commit hook's path-leak
# scan is the constraint's only other seam, and it catches a work-directory prefix, not a
# bare path segment — this line must name no path at all.
if [ "$step3b_status" -ne 0 ]; then
    fail "review-mr.md's ### Step 3b wiring instruction names no path" "extraction failed (exit $step3b_status): $step3b_error"
elif [ -z "$step3b_output" ]; then
    fail "review-mr.md's ### Step 3b wiring instruction names no path" "anchor found, section body is empty"
else
    ci_line=$(printf '%s\n' "$step3b_output" | $GREP -F 'what CI selects')
    if [ -z "$ci_line" ]; then
        fail "review-mr.md's ### Step 3b wiring instruction names no path" "no line contains 'what CI selects'"
    elif printf '%s' "$ci_line" | $GREP -qF '/'; then
        fail "review-mr.md's ### Step 3b wiring instruction names no path" "the 'what CI selects' line contains a '/': $ci_line"
    else
        pass "review-mr.md's ### Step 3b wiring instruction names no path"
    fi
fi

# Row 7: two consumers slicing at different bounds with nothing saying so. Both sides must
# extract successfully before comparing — two failed extractions would otherwise both read
# as empty and compare equal, passing while neither file states a bound.
research_rows=$(prior_rows_value "$research_output")
step3b_rows=$(prior_rows_value "$step3b_output")
if [ -z "$research_rows" ] || [ -z "$step3b_rows" ]; then
    fail "research.md and review-mr.md declare the same PRIOR_CONTEXT_ROWS value" \
         "research.md extracted '$research_rows', review-mr.md extracted '$step3b_rows' — one or both are empty"
elif [ "$research_rows" = "$step3b_rows" ]; then
    pass "research.md and review-mr.md declare the same PRIOR_CONTEXT_ROWS value ($research_rows)"
else
    fail "research.md and review-mr.md declare the same PRIOR_CONTEXT_ROWS value" \
         "research.md=$research_rows review-mr.md=$step3b_rows"
fi

# Every agent that takes outside content points at the one place the rule lives. The
# fragment is the single source; an agent file rewritten without the pointer loses the
# rule silently, which is the drift this pins.
uc_fragment="$CLAUDE/skills/workflows/untrusted-content/SKILL.md"
uc_missing=""
for uc_agent in "$CLAUDE"/agents/*.md; do
    $GREP -qF 'untrusted-content/SKILL.md' "$uc_agent" || uc_missing="$uc_missing $(basename "$uc_agent")"
done
if [ ! -s "$uc_fragment" ]; then
    fail "every agent points at the untrusted-content fragment" \
         "the fragment itself is missing or empty at skills/workflows/untrusted-content/SKILL.md"
elif [ -n "$uc_missing" ]; then
    fail "every agent points at the untrusted-content fragment" \
         "no pointer in:$uc_missing"
else
    pass "every agent points at the untrusted-content fragment"
fi

echo "== Command files: fix-mr.md's fetch/diff/placeholder shell text =="

# fix-mr.md is Markdown an agent reads, not a script a harness runs, so a regression in its
# shell text stays invisible until someone reads the right paragraph. These four give it a surface.
FIXMR="$CLAUDE/commands/fix-mr.md"
FIXMR_FETCH_CMD_COUNT=2      # Step 3a + Step 4a — bump when fix-mr.md gains or loses a fetch call
FIXMR_SHELL_BLOCK_COUNT=6    # ```bash/```sh/```shell fenced blocks in fix-mr.md — bump likewise

# Shared scope-limiters: confine every scan below to fix-mr.md's own fenced/inline shell text, never the whole file.
fixmr_fenced_lines() {   # emits only lines inside a ```bash/```sh/```shell fenced block
    awk '/^```(bash|sh|shell)/{f=1;next} /^```$/{f=0;next} f' "$FIXMR"
}
fixmr_full_block_containing() {   # $1: marker string; emits the first fenced block's full body containing it
    awk -v marker="$1" '
      /^```(bash|sh|shell)/ { buf=""; instream=1; next }
      /^```$/ { if (instream && index(buf, marker)) { printf "%s", buf; exit } instream=0; next }
      instream { buf = buf $0 "\n" }
    ' "$FIXMR"
}
fixmr_unsafe_placeholder() {   # emits lines carrying a <placeholder> outside single quotes/a comment
    awk '
      {
        in_dq=0; in_sq=0; hit=0
        n=length($0)
        for (i=1; i<=n; i++) {
          c=substr($0,i,1)
          if (!in_sq && c=="\"")   { in_dq = !in_dq; continue }
          if (!in_dq && c=="\047") { in_sq = !in_sq; continue }
          if (!in_sq && !in_dq && c=="#") { break }
          if (!in_sq && c=="<") {
            rest=substr($0,i)
            if (match(rest, /^<[A-Za-z0-9_-]+>/)) { hit=1 }
          }
        }
        if (hit) print
      }
    '
}

# 1: an unforced or name-swapped refspec breaks or misdirects the merge-base; scoped to fenced COMMAND lines.
fetch_cmd_lines=$(fixmr_fenced_lines | $GREP -F 'git fetch origin' | $GREP -v '^[[:space:]]*echo ')
n_fetch_cmd=$(printf '%s\n' "$fetch_cmd_lines" | $GREP -c . || true)
unforced=$(printf '%s\n' "$fetch_cmd_lines" | $GREP -oE '[^+]<[A-Za-z_]+>:refs/remotes/origin/<[A-Za-z_]+>' || true)
forced=$(printf '%s\n' "$fetch_cmd_lines" | $GREP -oE '\+<[A-Za-z_]+>:refs/remotes/origin/<[A-Za-z_]+>' || true)
n_forced=$(printf '%s\n' "$forced" | $GREP -c . || true)
mismatched=$(printf '%s\n' "$forced" | $GREP -vE '^\+<([A-Za-z_]+)>:refs/remotes/origin/<\1>$' || true)
if [ "$n_fetch_cmd" -ne "$FIXMR_FETCH_CMD_COUNT" ]; then
    fail "fix-mr.md has $FIXMR_FETCH_CMD_COUNT 'git fetch origin' command line(s), each refspec forced with a leading + and its source/destination names matching" \
         "found $n_fetch_cmd command line(s) — extraction drifted from the expected literal"
elif [ -n "$unforced" ]; then
    fail "fix-mr.md has $FIXMR_FETCH_CMD_COUNT 'git fetch origin' command line(s), each refspec forced with a leading + and its source/destination names matching" \
         "unforced refspec(s): $(printf '%s' "$unforced" | tr '\n' ' ')"
elif [ "$n_forced" -ne $((FIXMR_FETCH_CMD_COUNT * 2)) ]; then
    fail "fix-mr.md has $FIXMR_FETCH_CMD_COUNT 'git fetch origin' command line(s), each refspec forced with a leading + and its source/destination names matching" \
         "expected $((FIXMR_FETCH_CMD_COUNT * 2)) forced refspecs (2 per line), found $n_forced — a refspec may be missing outright, not merely unforced"
elif [ -n "$mismatched" ]; then
    fail "fix-mr.md has $FIXMR_FETCH_CMD_COUNT 'git fetch origin' command line(s), each refspec forced with a leading + and its source/destination names matching" \
         "refspec(s) with swapped source/destination placeholder names: $(printf '%s' "$mismatched" | tr '\n' ' ')"
else
    pass "fix-mr.md's $FIXMR_FETCH_CMD_COUNT 'git fetch origin' command line(s) carry $n_forced forced refspecs, none unforced, none with swapped names"
fi

# 2: --enable=check-unassigned-uppercase catches an ALL-CAPS var like BATCH that shellcheck's 0.9.0
# default otherwise presumes is an env var; SC2154 stays suppressed for a -z/-n-only use.
blocks_dir=$(mktemp -d) && [ -d "$blocks_dir" ] || blocks_dir=""
if [ -z "$blocks_dir" ]; then
    fail "fix-mr.md has $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s), each clean under shellcheck -s bash" \
         "mktemp -d failed to create a scratch directory"
else
    awk -v dir="$blocks_dir" '
      /^```(bash|sh|shell)/ { n++; f=dir "/" n; print "" > f; next }
      /^```$/    { if (f) { close(f); f="" } ; next }
      f          { print >> f }
    ' "$FIXMR"
    n_blocks=$(find "$blocks_dir" -type f | wc -l)
    bad=""
    for blk in "$blocks_dir"/*; do
        [ -f "$blk" ] || continue
        sc_out=$(shellcheck -s bash --enable=check-unassigned-uppercase "$blk" 2>&1) || bad="$bad$(basename "$blk"): $sc_out\n"
    done
    rm -rf "$blocks_dir"
    if [ "$n_blocks" -ne "$FIXMR_SHELL_BLOCK_COUNT" ]; then
        fail "fix-mr.md has $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s), each clean under shellcheck -s bash" \
             "found $n_blocks block(s) — extraction drifted from the expected literal"
    elif [ -n "$bad" ]; then
        fail "fix-mr.md has $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s), each clean under shellcheck -s bash" "$(printf "%b" "$bad")"
    else
        pass "all $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s) in fix-mr.md are clean under shellcheck -s bash"
    fi
fi

# 3: shell state does not cross a fence, so each block must keep its own branch, guard, and echo.
step3a_block=$(fixmr_full_block_containing 'Lens A: failed')
step3b_block=$(fixmr_full_block_containing 'wc -c')
step4a_block=$(fixmr_full_block_containing 'flag: unavailable')
bad=""
if [ -z "$step3a_block" ]; then
    bad="${bad}Step 3a's block (containing 'Lens A: failed') not found — extraction broken; "
else
    printf '%s\n' "$step3a_block" | $GREP -qE '^if ! git fetch' \
        || bad="${bad}Step 3a's fetch is no longer branched on (missing leading 'if !'); "
    printf '%s\n' "$step3a_block" | $GREP -qE '^[[:space:]]*base=\$\(git merge-base' \
        || bad="${bad}Step 3a's block no longer assigns \$base; "
    printf '%s\n' "$step3a_block" | $GREP -qF -- '-z "$base"' \
        || bad="${bad}Step 3a's block assigns \$base but its -z \"\$base\" guard is gone; "
    n_stdout_echo=$(printf '%s\n' "$step3a_block" | $GREP -E '^[[:space:]]*echo ' | $GREP -v '>&2' | $GREP -c . || true)
    if [ "$n_stdout_echo" -ne 1 ]; then
        bad="${bad}Step 3a's block prints $n_stdout_echo value(s) to stdout via echo, expected exactly 1; "
    else
        printf '%s\n' "$step3a_block" | $GREP -qE '^[[:space:]]*echo "\$base"[[:space:]]*$' \
            || bad="${bad}Step 3a's block prints exactly one value to stdout but it is not \$base; "
    fi
fi
if [ -z "$step3b_block" ]; then
    bad="${bad}Step 3b's diff-measurement block not found — extraction broken; "
else
    printf '%s\n' "$step3b_block" | $GREP -qE '^[[:space:]]*set -o pipefail[[:space:]]*$' \
        || bad="${bad}Step 3b's wc -c measurement block no longer sets -o pipefail; "
    printf '%s\n' "$step3b_block" | $GREP -qE '^[[:space:]]*echo .*\$diff_bytes.*\$diff_rc' \
        || bad="${bad}Step 3b's block assigns \$diff_bytes/\$diff_rc but has no echo naming \$diff_bytes before \$diff_rc; "
fi
if [ -z "$step4a_block" ]; then
    bad="${bad}Step 4a's block (containing 'flag: unavailable') not found — extraction broken; "
else
    printf '%s\n' "$step4a_block" | $GREP -qE '^[[:space:]]*base=\$\(git merge-base' \
        || bad="${bad}Step 4a's block reads \$base but no longer assigns it — it must re-derive its own merge-base; "
    printf '%s\n' "$step4a_block" | $GREP -qF -- '-z "$base"' \
        || bad="${bad}Step 4a's block assigns \$base but its -z \"\$base\" guard is gone; "
fi
if [ -z "$bad" ]; then
    pass "Step 3a branches on its fetch and echoes its guarded \$base exactly once, Step 3b's wc -c block runs under set -o pipefail and echoes \$diff_bytes before \$diff_rc, and Step 4a re-derives and guards its own \$base"
else
    fail "Step 3a branches on its fetch and echoes its guarded \$base exactly once, Step 3b's wc -c block runs under set -o pipefail and echoes \$diff_bytes before \$diff_rc, and Step 4a re-derives and guards its own \$base" "$bad"
fi

# 4: single quotes are required at every real point of use, not inside a comment, including Step 1a's shell use outside any fence.
placeholder_unsafe_hits=$(fixmr_fenced_lines | fixmr_unsafe_placeholder)
n_bash_blocks=$($GREP -cE '^```(bash|sh|shell)' "$FIXMR" || true)
step1a_line=$($GREP -m1 -F '**1a. One load.**' "$FIXMR")
step1a_span=$(printf '%s' "$step1a_line" | $GREP -oE '`[^`]*`' | head -1 | tr -d '`')
step1a_unsafe=$(printf '%s\n' "$step1a_span" | fixmr_unsafe_placeholder)
if [ "$n_bash_blocks" -ne "$FIXMR_SHELL_BLOCK_COUNT" ]; then
    fail "fix-mr.md has $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s), no placeholder outside single quotes in any, plus Step 1a's inline command" \
         "found $n_bash_blocks block(s) — extraction drifted from the expected literal"
elif [ -z "$step1a_span" ]; then
    fail "fix-mr.md has $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s), no placeholder outside single quotes in any, plus Step 1a's inline command" \
         "Step 1a's inline projctl command span was not found — extraction broken"
elif [ -n "$placeholder_unsafe_hits" ] || [ -n "$step1a_unsafe" ]; then
    fail "fix-mr.md has $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s), no placeholder outside single quotes in any, plus Step 1a's inline command" \
         "fenced block(s): $placeholder_unsafe_hits Step 1a: $step1a_unsafe"
else
    pass "all $FIXMR_SHELL_BLOCK_COUNT fenced shell block(s) in fix-mr.md, plus Step 1a's inline projctl command, keep every placeholder single-quoted at its point of use"
fi

echo
total=$((PASS + FAIL))
[ "$total" -eq "$EXPECTED_TESTS" ] \
    && pass "all $EXPECTED_TESTS assertions ran" \
    || fail "all $EXPECTED_TESTS assertions ran" "ran $total — a block skipped itself or EXPECTED_TESTS is stale"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
