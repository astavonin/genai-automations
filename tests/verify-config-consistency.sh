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

# Bump when adding or removing an assertion. Asserted at the end so a block that silently
# skips itself shows up as a count mismatch instead of a green run — the sibling suite
# (verify-workflow-safety.sh) added this counter for the same reason; this suite had none,
# which is finding T3 in planning/genai-automations/appendix-page-type.
EXPECTED_TESTS=40

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
# present and every requirement bullet carries a real From: tag.
tmpl_out=$(doc-metrics "$DESIGN_TEMPLATE" 2>&1); tmpl_rc=$?
bad=""
[ "$tmpl_rc" -eq 0 ] || bad="doc-metrics exited $tmpl_rc; "
for counter in COST MISSES FROM UNTAGGED; do
    v=$(metric "$tmpl_out" "$counter")
    [ "$v" = "0" ] || bad="$bad$counter=${v:-<no line>}; "
done
if [ -z "$bad" ]; then
    pass "the shipped DESIGN-TEMPLATE.md reports zero on all four design-field counters"
else
    fail "the shipped DESIGN-TEMPLATE.md reports zero on all four design-field counters" \
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
# proves nothing about this step. The span runs from the step 8 opener to the next `## `.
VERIFY_DOC="$CLAUDE/commands/verify.md"
span=$(awk '/^8\. \*\*Attribution/{f=1} f&&/^## /{exit} f' "$VERIFY_DOC")
if [ -n "$span" ] \
    && printf '%s' "$span" | $GREP -q 'refs/remotes/origin/HEAD' \
    && printf '%s' "$span" | $GREP -q 'ls-files --others' \
    && printf '%s' "$span" | $GREP -q 'say so in one line'; then
    pass "/verify's attribution step resolves the base, sees unstaged files, and documents the no-source skip"
else
    fail "/verify's attribution step resolves the base, sees unstaged files, and documents the no-source skip" \
         "$(printf '%s' "${span:-<no step 8 span found>}" | head -4)"
fi

echo
total=$((PASS + FAIL))
[ "$total" -eq "$EXPECTED_TESTS" ] \
    && pass "all $EXPECTED_TESTS assertions ran" \
    || fail "all $EXPECTED_TESTS assertions ran" "ran $total — a block skipped itself or EXPECTED_TESTS is stale"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
