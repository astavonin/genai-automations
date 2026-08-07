#!/usr/bin/env bash
# doc-metrics.sh — per-section prose-word and defensive-register counts for Markdown docs.
#
# The unit is PROSE WORDS: words outside fenced blocks and headings, plus table cell text at
# half weight. `wc -l` misleads on these documents because the repo bans manual line wrapping,
# so one paragraph is one line and a 1,741-character paragraph counts as 1. Table cells count
# at half because tabulating is genuine compression and should be rewarded — but excluding
# them outright let a section go from 5,022 words to 0 by wrapping every line in pipes, with
# the text unchanged. Register is counted at full weight everywhere outside a fence: a
# defensive sentence is defensive wherever it sits.
#
# This script owns the per-section targets and ceilings. Nothing else publishes them.
#
# Usage:   doc-metrics.sh <file.md> [<file.md> ...]
#
# Exit codes:
#   0  ran — read the output
#   1  BLOCKER — bad input, or a measurement that cannot be trusted (see below)
#
# A non-zero exit means "this number is not a measurement", never "hits found" or "over
# ceiling". Callers read the REGISTER and CEILING summary lines for those. Blocking cases:
# missing, unreadable, or placeholder path; NUL bytes; missing or failing awk; an awk that
# ran without producing a table; an unclosed fence; and a setext heading, which is not
# treated as a section boundary and would otherwise silently merge two sections' budgets.
#
# Known limits, none of which affect a document following DESIGN-TEMPLATE.md:
#   - A pipe table without leading pipes counts as prose.
#   - Inline code containing spaces counts one word per space-separated token.
#   - Overlapping register phrases both count ("note that said" is two hits).
#   - A register phrase split across a line break is not seen; scanning is per line, and
#     the repo bans manual wrapping inside a paragraph, so this needs an authored break.
#   - An escaped pipe inside a table cell splits the cell into two words.
#   - Non-Latin LETTERS outside the common scripts (Roman numerals, Braille, Deseret,
#     mathematical alphanumerics) are treated as symbols and do not count as words.
#   - Section rows are addressed by exact name, not by prefix: a section called TOTAL is
#     renamed to "TOTAL (2)", but a caller matching /^TOTAL/ still sees both it and the
#     summary row. Match the whole first field, as tests/verify-doc-metrics.sh does.
#
# Tests: tests/verify-doc-metrics.sh in the genai-automations repo (not installed alongside
#        this script; run it there after editing).

# Byte-oriented awk and a '.' decimal separator. This pin is required for EXECUTION, not just
# for consistency: the byte-range regexes in count_words are invalid collation ranges in a
# UTF-8 locale and gawk aborts on them. It also stops gawk padding %-38s by characters while
# mawk pads by bytes, and stops mawk rendering %.1f as "25,0%" under a comma-decimal locale.
export LC_ALL=C

set -uo pipefail

AWK="${DOC_METRICS_AWK:-awk}"
if ! command -v "$AWK" >/dev/null 2>&1; then
    echo "BLOCKER: awk interpreter not found: $AWK" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    echo "BLOCKER: no file given — usage: doc-metrics.sh <file.md> [<file.md> ...]" >&2
    exit 1
fi

for f in "$@"; do
    case "$f" in
        *"<"*) echo "BLOCKER: placeholder left in path — $f" >&2; exit 1 ;;
    esac
    case "$f" in
        *"
"*) echo "BLOCKER: newline in path" >&2; exit 1 ;;
    esac
    if [ ! -f "$f" ]; then
        echo "BLOCKER: not a file — $f" >&2
        exit 1
    fi
    # Checked before the NUL test: an unreadable file makes `wc -c` print nothing while the
    # `tr` pipeline still prints 0, so the NUL comparison fires and misdiagnoses it.
    if [ ! -r "$f" ]; then
        echo "BLOCKER: not readable — $f" >&2
        exit 1
    fi
    # NUL bytes make awk implementations disagree on where a line ends, and one of them
    # silently drops register hits. Refuse rather than report a per-interpreter number.
    if [ "$(wc -c < "$f")" != "$(tr -d '\000' < "$f" | wc -c)" ]; then
        echo "BLOCKER: NUL bytes in $f — not a text document" >&2
        exit 1
    fi
done

STATUS=$(mktemp) || { echo "BLOCKER: mktemp failed" >&2; exit 1; }
trap 'rm -f "$STATUS"' EXIT

for f in "$@"; do
    OUT=$("$AWK" -v F="$f" '
      BEGIN {
        # Defensive-register detector list. NON-EXHAUSTIVE by construction: banning one
        # token yields substitutes, so the rule outranks this list and a zero count is not
        # proof the rule is met. Matching is whole-word and case-insensitive; multi-word
        # entries must appear as consecutive words with no sentence break between them.
        NREG = split("deliberately|intentionally|by design|which is what makes|worth noting|it should be noted|note that|importantly|crucially|essentially|fundamentally|in other words|that said|of course", R, "|")
        for (r = 1; r <= NREG; r++) {
          reg_n[r] = split(R[r], tmp, " ")
          for (k = 1; k <= reg_n[r]; k++) reg_words[r, k] = tmp[k]
        }

        # Quote characters marking a mention rather than a use: backtick, double quote,
        # apostrophe, and the curly and guillemet forms a prose document actually uses.
        # Built with sprintf because the whole program is a single-quoted shell string, so
        # a literal apostrophe here would terminate it.
        QC = "`" sprintf("%c%c", 34, 39) "\342\200\230\342\200\231\342\200\234\342\200\235\302\253\302\273\342\200\236"

        # Per-section targets: the canonicalised median across all 39 corpus documents.
        # CEILINGS EXIST ONLY FOR SLOTS 5 AND 6 AND THE DOCUMENT. A p75 ceiling on all eight
        # slots blocked 20 of 39 existing documents, most of them on a small section
        # carrying no bloat; slots without a ceiling report an advisory verdict only.
        # cap[5] is the measured p75. cap[6] is 2x its target rather than the measured p75:
        # slot 6 has the smallest sample and a bimodal pool, so its p75 moves 10% with one
        # more document (bootstrap 90% CI 877-2334) and would not be a stable gate.
        tgt["1"] = 184;  tgt["2"] = 283;  tgt["3"] = 441;  tgt["4"] = 129
        tgt["5"] = 4232; tgt["6"] = 877;  tgt["7"] = 580;  tgt["8"] = 45
        cap["5"] = 5463; cap["6"] = 1754
        DOC_TGT = 5800; DOC_CAP = 8322

        # A section literally named TOTAL would collide with the summary row for a caller
        # matching the whole first field. Reserve the name so unique() renames it; a caller
        # matching only the /^TOTAL/ prefix is not protected (see Known limits).
        seen["TOTAL"] = 1
        sec = "(preamble)"
        nhit = 0; nsec = 0; prevprose = 0

        # Design-field state (mechanism-proportionality): slot 7 tracks one open ### option
        # block at a time; slot 3 tracks the current requirement-group state. Both reset per
        # section change, mirroring how word/register accumulation is already section-scoped.
        opt_open = 0; opt_cost = 0; opt_miss_val = 0; opt_loc = ""
        # D6: the column a bare Misses: label was seen in, in a table row whose own cells
        # (its own cell and the next one over) never supplied a value — a label-row/value-row
        # table layout puts the value in the SAME column of the NEXT table row instead
        # ("| **Cost:** | **Misses:** |" over "| ~1 LOC | none |"). Reset alongside
        # opt_cost/opt_miss_val: see the H3+ heading rule below for why the reset lives at
        # block-OPEN rather than at close_opt_block().
        miss_pending_col = 0
        slot7_block_ever = 0
        # req_scan_bullets is a THIRD axis, independent of req_group: req_group == "req" means
        # a From: tag on a bullet here is inline-in-a-group (not misplaced), true for both a
        # validly-opened group and a spaced-colon near-miss (H1) — the _collect_bullets()
        # helper in markdown_parser.py strips the label before comparing it to the field name, so a
        # spaced-colon opener really is collected as a live group in production and an inline
        # tag beneath it really is valid. req_scan_bullets narrows that to "also flag a bullet
        # with NO tag at all", which stays off for the near-miss: the malformed opener itself
        # already reports once, and scoring every bullet beneath it too would scale the same
        # defect by bullet count instead of stating it once, undoing the "one hit already tells
        # the author where to look" property the near-miss branch exists for.
        req_group = ""; req_scan_bullets = 0; req_close_loc = ""
        COST = 0; MISSES = 0; FROM = 0; UNTAGGED = 0; nfhit = 0

        # D4: the From: value first-tokens from_valid() accepts, declared exactly once so
        # tests/verify-doc-metrics.sh (I6) can read this literal directly instead of
        # re-deriving the accepted set by scanning the from_valid() body for quoted tokens — a
        # scan that a same-shaped literal ANYWHERE in the window (a comment, a stray string)
        # could feed just as easily as a real value, and that cannot see a value accepted
        # through a comparison other than a literal == at all (a from_valid() rewritten to
        # test a token with `~` instead of enumerating it here would not add a new quoted
        # literal for the old scan to catch). "bare": the token alone is sufficient (analysis).
        # "value": a second token, any text (ticket, spec). "date": a second token in strict
        # YYYY-MM-DD form (incident, decision). from_valid() below reads ONLY this table —
        # every first-token comparison it makes is array membership, not a literal or a
        # pattern, so widening the accepted set means editing this one line, and I6 then
        # catches a mismatch against the documented five in DESIGN-TEMPLATE.md without having
        # to understand HOW from_valid() tests a token. An unrecognised first token reads
        # from_kind[] as "" by ordinary awk array-reference semantics (referencing an absent
        # key creates it empty rather than erroring) — the trailing return 0 in from_valid()
        # already covers that case, so no separate membership array is kept here.
        FROM_N = split("analysis:bare ticket:value spec:value incident:date decision:date", FROM_L, " ")
        for (fi = 1; fi <= FROM_N; fi++) {
          split(FROM_L[fi], fkv, ":")
          from_kind[fkv[1]] = fkv[2]
        }
      }

      # Strip CR so CRLF files tokenise like LF ones. Without this the CR rides along into
      # section names and snippets and breaks the columns.
      { sub(/\r$/, "") }

      # YAML frontmatter is metadata, not prose. Its closing --- also looks exactly like a
      # setext underline following a content line, which made every agent and command file
      # in this config BLOCK.
      NR == 1 && /^(\357\273\277)?---[ \t]*$/ { fm = 1; next }
      # A leading --- is only frontmatter when a YAML key follows it. Otherwise it is a
      # horizontal rule, and treating it as an opener discarded every line up to the next ---.
      fm && NR == 2 && $0 !~ /^[A-Za-z_][A-Za-z0-9_.-]*[ \t]*:/ { fm = 0 }
      fm { if ($0 ~ /^---[ \t]*$/) fm = 0; next }

      # Fence tracking. The opener character and its run length are both recorded: a
      # four-backtick fence must not be closed by a three-backtick line, which is exactly
      # the shape a document uses to show a fence example. Indent is capped at 3 per
      # CommonMark, so a 4-space-indented ``` inside a heredoc is content, not a fence.
      {
        fl = $0
        # A blockquote marker is stripped when the line is outside a fence, or inside one
        # that was itself opened in a blockquote. Stripping unconditionally let a
        # blockquoted fence line close a plain enclosing block and leak its content;
        # never stripping left a blockquoted fence unable to close itself.
        isq = (fl ~ /^([ \t]*>)+/)
        # A fence opened inside a blockquote ends with the blockquote. Without this the
        # fence stayed open over the rest of the document and every following paragraph
        # was discarded, register and all, at exit 0.
        if (fence && fquote && !isq) { fence = 0; fquote = 0 }
        if (!fence || fquote) sub(/^([ \t]*>)+[ \t]*/, "", fl)
        if (match(fl, /^ ? ? ?(`+|~+)/)) {
          run = fl; sub(/^[ ]*/, "", run)
          fc = substr(run, 1, 1)
          rl = 0
          while (substr(run, rl + 1, 1) == fc) rl++
          if (rl >= 3) {
            if (!fence) { fence = 1; fchar = fc; flen = rl; fquote = isq }
            else if (fc == fchar && rl >= flen && substr(run, rl + 1) ~ /^[ \t]*$/) {
              # A closing fence carries no info string (CommonMark). Without this test a
              # ```yaml line inside an open block reads as its closer and every fence after
              # it is inverted.
              fence = 0
            }
            prevprose = 0
            next
          }
        }
      }
      fence { next }

      # A setext underline turns the preceding line into a heading. Supporting that means
      # retracting the previous line from its section, so this BLOCKs instead: treating the
      # heading as prose merges two sections into one budget, and a zero ceiling count on a
      # document whose sections were silently merged is the same lie as counting past an
      # unclosed fence. Only fires after a PROSE line — a --- after a blank line, a fence, a
      # heading, or a table row is a horizontal rule, which DESIGN-TEMPLATE uses throughout.
      /^[ \t]*(=+|--+)[ \t]*$/ {
        if (prevprose) setext++
        prevprose = 0
        next
      }

      # H1 and H2 open a section; H3 and deeper roll up into the enclosing section, which is
      # the documented contract. `#` must open one: without it, prose under a mid-document
      # H1 was attributed to the last `##`. No interval quantifier anywhere in this program:
      # some mawk builds ignore them, and a static test in the suite forbids them.
      /^##?[ \t]/ {
        # Close design-field state for the section being left, before it is overwritten:
        # the H1/H2 branch closes any open option block on a section change, and fires the
        # no-block-opened warning for a slot-7 section that closes having opened none, and
        # the counterpart warning for a slot-3 section that closes having opened no
        # requirement group at all (M2 — the mention hole slot 7 already had a closer for).
        close_opt_block()
        close_slot7_section()
        close_slot3_section()
        # req_scan_bullets does not live inside close_slot3_section(): it is set at every
        # req_group == "req" assignment site (both branches below), so it must be cleared here
        # too, or a section that ends INSIDE an open group (no closing label, no malformed
        # opener afterward) leaks its 1 into field_scan calls for the next slot-3 section,
        # before that section own opener, if any, is seen.
        req_group = ""; req_scan_bullets = 0
        h = heading_text($0)
        sec = unique(h)
        register_section(sec)
        # The first H1 is the document title. Five corpus titles matched the Test rule,
        # two of them in documents with no test section at all, dragging that slot down.
        if ($0 ~ /^#[ \t]/ && !seentitle) { seentitle = 1; istitle[sec] = 1 }
        # Scanned AFTER the switch: a hit in a heading belongs to the section the heading
        # opens, not to the one it closes.
        scan_register(h, sec)
        prevprose = 0
        next
      }

      # H3 and deeper: structure, so no words, but its register belongs to the author.
      # In slot 7 an EXACT H3 (not H4+) opens a new option block, closing any already open —
      # heading text is not inspected, so a §7 sub-heading omitting the word "Option" still
      # opens one. H4+ opens no block: a sub-heading inside an option belongs to that option.
      /^###+[ \t]/ {
        h3 = heading_text($0)
        scan_register(h3, sec)
        if (match($0, /^#+/) && RLENGTH == 3 && canon(sec) == "7") {
          close_opt_block()
          opt_open = 1; opt_cost = 0; opt_miss_val = 0
          miss_pending_col = 0
          opt_loc = h3
          slot7_block_ever = 1
        }
        # D3: in slot 3, ANY heading level 3+ naming one of the three requirement-group labels
        # is a malformed opener — the valid form is inline bold text, never a heading, at any
        # depth. This line never reaches field_scan at all (this rule already `next`s past it),
        # so it is the only place that can catch this shape. Reported the instant it is seen,
        # like the spaced-colon near-miss in field_scan below — independent of req_group state
        # and of whatever else the section does or does not contain (D3).
        if (canon(sec) == "3" && h3 ~ /^(Functional Requirements|Non-Functional Requirements|Constraints):?$/) {
          UNTAGGED++
          record_field_hit(sec, h3, "requirement group opener written as a heading, not inline bold text")
        }
        prevprose = 0
        next
      }

      # Table rows: cell text counts at half weight, register at full. The blockquote
      # marker is stripped first, or a quoted row fell through to the prose branch and was
      # charged at full weight.
      /^([ \t]*>)*[ \t]*\|/ {
        register_section(sec)
        cells = $0
        sub(/^([ \t]*>)+[ \t]*/, "", cells)
        gsub(/\|/, " ", cells)
        halfwords[sec] += count_words(cells)
        scan_register($0, sec)
        field_scan($0, sec)
        prevprose = 0
        next
      }

      /^[ \t]*$/ { prevprose = 0; next }

      {
        # A --- after a list item or a blockquote is a thematic break, not a setext
        # underline, so those lines do not arm the setext test.
        prevprose = ($0 ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]|^[ \t]*>/) ? 0 : 1
        line = $0
        sub(/^([ \t]*>)+[ \t]?/, "", line)              # blockquote markers
        sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", line)  # list marker

        register_section(sec)
        halfwords[sec] += 2 * count_words(line)
        scan_register(line, sec)
        # Raw $0, not the marker-stripped `line`: stripping the list marker puts a bold
        # label that opens a bullet at position 0, where the line-start test would misread
        # it as a group opener or a misplaced From: tag (§5.3).
        field_scan($0, sec)
      }

      END {
        if (fence) {
          printf "BLOCKER: unclosed %s fence in %s — content after it was not counted.\n", \
                 substr("``` ~~~", (fchar == "`" ? 1 : 5), 3), F > "/dev/stderr"
          # Usually a same-length nested fence: the inner one closes the outer, as a strict
          # renderer also reads it. DESIGN-TEMPLATE avoids this by using ~~~ outside ```.
          printf "         If a block nests another, make the outer fence ~~~ or four backticks.\n" \
                 > "/dev/stderr"
          exit 1
        }
        if (fm) {
          printf "BLOCKER: unclosed YAML frontmatter in %s — the whole document was skipped.\n", \
                 F > "/dev/stderr"
          exit 1
        }
        if (setext) {
          printf "BLOCKER: %d setext heading(s) in %s — not treated as section boundaries,\n", \
                 setext, F > "/dev/stderr"
          printf "         so their sections would share one budget. Use ## headings.\n" > "/dev/stderr"
          exit 1
        }

        # Close whatever design-field state the document ended in: the last open option
        # block, a final slot-7 section that closed having opened none, and a final slot-3
        # section that closed having opened no requirement group.
        close_opt_block()
        close_slot7_section()
        close_slot3_section()

        total = 0; totreg = 0; over = 0
        for (s = 1; s <= nsec; s++) {
          nm = order[s]
          words[nm] = int(halfwords[nm] / 2)
          total += words[nm]
          totreg += reg[nm]
          slot = canon(nm)
          if (slot != "") { slotw[slot] += words[nm]; slotrows[slot]++ }
          else if (words[nm] > 0) { unslot++; unslotw += words[nm] }
        }

        print "== " F " =="
        printf "%-38s\t%7s\t%7s\t%5s\t%7s\t%7s\t%s\n", \
               "section", "words", "share", "reg", "target", "ceiling", "verdict"
        for (s = 1; s <= nsec; s++) {
          nm = order[s]
          sh = (total > 0) ? sprintf("%.1f%%", 100 * words[nm] / total) : "-"
          slot = canon(nm)
          t = (slot == "") ? "-" : tgt[slot] ""
          c = (slot == "" || !(slot in cap)) ? "-" : \
              ((slotrows[slot] > 1) ? slotw[slot] "/" cap[slot] : cap[slot] "")
          printf "%-38s\t%7d\t%7s\t%5d\t%7s\t%7s\t%s\n", nm, words[nm], sh, reg[nm], t, c, \
                 (slot == "") ? "-" : verdict(slot)
        }
        dv = (total > DOC_CAP) ? "OVER-CEILING" : ((total > DOC_TGT) ? "over-target" : "ok")
        if (total > DOC_CAP) over++
        # Counted per SLOT, not per row: splitting one section into two headings, or
        # repeating a heading, otherwise multiplied the budget.
        for (slot in cap) if ((slot in slotw) && slotw[slot] > cap[slot]) over++
        printf "%-38s\t%7d\t%7s\t%5d\t%7s\t%7s\t%s\n", "TOTAL", total, "-", totreg, DOC_TGT, DOC_CAP, dv

        if (nhit > 0) {
          print ""
          print "register hits (detector list is non-exhaustive; the rule outranks it):"
          for (h = 1; h <= nhit; h++)
            printf "  %s\t%s\t%s\n", hit_sec[h], hit_tok[h], hit_txt[h]
        }
        print ""
        print "REGISTER: " totreg " hit(s)"
        print "CEILING: " over " slot(s) over ceiling"
        # A heading that matches no slot has no ceiling, so a large unslotted section is
        # invisible to the length gate. Reported rather than blocked: a design doc
        # legitimately carries feature-specific sections.
        print "UNSLOTTED: " unslot " section(s) holding " unslotw " word(s)"

        # Four design-field counters print unconditionally, like the three above, so a zero
        # reads as checked-and-clean rather than not-checked. This script states counts, not
        # verdicts — /verify-docs owns the warn-versus-block split.
        print "COST: " COST " option block(s) or option-less section(s) with no Cost line"
        print "MISSES: " MISSES " Cost line(s) with no Misses value"
        print "FROM: " FROM " misplaced or unrecognised From tag(s)"
        # M11: widened for the same reason COST was — UNTAGGED also carries a malformed
        # group-opener hit (heading-level, bulleted-label, or spaced-colon), none of which is
        # a bullet, so a bullet-only wording told an operator a tag was missing from a bullet
        # that was never examined. D3 dropped the section-level "group-less section" category
        # (a section-wide proxy that went silent behind an earlier valid group and fired on
        # any arbitrary bullet, malformed or not — see close_slot3_section()) in favour of the
        # three malformed-opener hits reporting for themselves, so the wording no longer
        # names it.
        print "UNTAGGED: " UNTAGGED " requirement bullet(s) with no From tag, or malformed requirement-group opener(s)"
        if (nfhit > 0) {
          print ""
          print "design-field hits (section, locator, reason):"
          for (h = 1; h <= nfhit; h++)
            printf "  %s\t%s\t%s\n", fhit_sec[h], fhit_loc[h], fhit_reason[h]
        }
      }

      # --- helpers ---------------------------------------------------------------

      # A heading name, normalised: markers and closing hashes removed, tabs folded to
      # spaces so they cannot break the tab-delimited output, whitespace runs collapsed.
      function heading_text(s,   h) {
        h = s
        sub(/^#+[ \t]+/, "", h)
        sub(/[ \t]+#+[ \t]*$/, "", h)
        gsub(/\t/, " ", h)
        gsub(/  +/, " ", h)
        sub(/[ ]+$/, "", h)
        if (h == "") h = "(unnamed heading)"
        return h
      }

      # A verdict for a slot, from its accumulated total rather than this row alone.
      function verdict(slot) {
        if ((slot in cap) && slotw[slot] > cap[slot]) return "OVER-CEILING"
        if (slotw[slot] > tgt[slot]) return "over-target"
        return "ok"
      }

      # A token is a word when it holds an ASCII alphanumeric, or a non-ASCII LETTER. The
      # letter test cannot be a byte floor: U+2014 (em dash) leads with 0xE2 and CJK leads
      # with 0xE3, so lead bytes do not separate punctuation from script. Instead the known
      # non-ASCII punctuation and symbol blocks are removed first and anything non-ASCII
      # still standing is treated as script.
      function count_words(s,   n, i, p, t, u, c) {
        n = split(s, p, /[ \t]+/)
        c = 0
        for (i = 1; i <= n; i++) {
          t = tolower(p[i])
          gsub(/[a-z0-9]/, "", t)
          u = p[i]
          # U+00A0-BF Latin-1 punctuation, carving out the three LETTERS in that block:
          # ordinal indicators U+00AA/U+00BA and micro sign U+00B5.
          gsub(/\302[\240-\251\253-\264\266-\271\273-\277]/, "", u)
          gsub(/\303\227|\303\267/, "", u)                # U+00D7 multiply, U+00F7 divide
          gsub(/\314[\200-\277]|\315[\200-\257]/, "", u)  # U+0300-036F combining marks
          gsub(/\342[\200-\257][\200-\277]/, "", u)       # U+2000-2BFF punctuation to symbols
          gsub(/\343\200[\201-\237]/, "", u)              # CJK punctuation and ideographic space
          gsub(/\357\274[\201-\277]/, "", u)              # fullwidth punctuation
          gsub(/[\360-\364][\200-\277][\200-\277][\200-\277]/, "", u)   # U+10000+ incl. emoji
          if (t != p[i] || u ~ /[\302-\377]/) c++
        }
        return c
      }

      # Count register phrases in one line and record each hit against `where`. Emission is
      # in document order — position outer, detector inner — so two hits on a line can be
      # told apart by their windows.
      function scan_register(s, where,   n, i, k, r, ok, nn, p, t, span, bt, was) {
        n = split(s, p, /[ \t]+/)
        nn = 0
        pend = 0
        span = 0
        for (i = 1; i <= n; i++) {
          t = tolower(p[i])
          gsub(/[^a-z0-9]/, "", t)
          # Span state is tracked for EVERY token, including ones that normalise away: a
          # span often opens on a token like `## that carries no alphanumeric at all, and
          # skipping it left the span closed for the words inside it.
          was = span
          bt = gsub(/`/, "`", p[i])
          if (bt % 2) span = !span
          if (t == "") {
            # A token that normalises away can still be a boundary — a bare "|" between two
            # table cells is the common case — so remember it for the next real word.
            if (p[i] ~ /[.:;!?|]/) pend = 1
            continue
          }
          nn++; nw[nn] = t; ow[nn] = p[i]
          insp[nn] = was
          if (pend && nn > 1) brk[nn - 1] = 1
          pend = 0
          # A phrase cannot span a sentence break or a cell boundary: "Take note. That is"
          # otherwise matched "note that".
          brk[nn] = (p[i] ~ /[.:;!?|][")]*$/) ? 1 : 0
        }
        if (nn == 0) return
        for (i = 1; i <= nn; i++) {
          for (r = 1; r <= NREG; r++) {
            if (i + reg_n[r] - 1 > nn) continue
            ok = 1
            for (k = 1; k <= reg_n[r]; k++) {
              if (nw[i + k - 1] != reg_words[r, k]) { ok = 0; break }
              if (k < reg_n[r] && brk[i + k - 1]) { ok = 0; break }
            }
            if (!ok || quoted(i, i + reg_n[r] - 1)) continue
            register_section(where)
            reg[where]++
            nhit++
            hit_sec[nhit] = where
            hit_tok[nhit] = R[r]
            hit_txt[nhit] = window(i, nn)
          }
        }
      }

      # True when the matched run is a mention rather than a use: it opens and closes with a
      # quote character, allowing markup before the opener and punctuation after the closer.
      # Both ends are stripped SYMMETRICALLY — stripping only *_ from the head made
      # ("deliberately") a violation while "of course") was exempt. A token merely inside a
      # longer quoted sentence matches neither end and still counts.
      function quoted(first, last,   f, l) {
        # Inside an inline code span that opened on an EARLIER word — the token then only
        # closes the span and its own first character is an ordinary letter, which the
        # symmetric test below cannot see. Testing for a backtick in the boundary token
        # instead over-exempted "on by `design`", where only the second word is code.
        if (insp[first] && insp[last]) return 1
        f = trim_head(ow[first])
        l = trim_tail(ow[last])
        return (index(QC, substr(f, 1, 1)) > 0 && index(QC, substr(l, length(l), 1)) > 0)
      }

      function trim_head(s,   c) {
        while (length(s) > 0) {
          c = substr(s, 1, 1)
          if (index(QC, c) > 0 || c ~ /[A-Za-z0-9]/ || c ~ /[\200-\377]/) break
          s = substr(s, 2)
        }
        return s
      }

      function trim_tail(s,   c) {
        while (length(s) > 0) {
          c = substr(s, length(s), 1)
          if (index(QC, c) > 0 || c ~ /[A-Za-z0-9]/ || c ~ /[\200-\377]/) break
          s = substr(s, 1, length(s) - 1)
        }
        return s
      }

      # Map a heading to a target slot by content, not by its number, so a document using
      # the older 7-section numbering still matches. Matching is on WHOLE WORDS — a
      # substring test put "Attestation" and "Contest Rules" in the Test slot — and the
      # trade-off rule precedes the test rule so "Trade-offs in Testing" lands in 7.
      function canon(nm,   n) {
        if (nm in istitle) return ""
        n = " " tolower(nm) " "
        gsub(/[^a-z0-9]+/, " ", n)
        if (n ~ / problem /)                             return "1"
        if (n ~ / goal | goals /)                        return "2"
        if (n ~ / implementation context /)              return "3"
        if (n ~ / architecture overview /)               return "4"
        if (n ~ / detailed design /)                     return "5"
        if (n ~ / trade off | trade offs | tradeoff | tradeoffs | alternative | alternatives /) return "7"
        if (n ~ / test | tests | testing /)              return "6"
        if (n ~ / open question | open questions | open item | open items /) return "8"
        # Fallbacks, after the exact template names: the corpus largest design section is
        # headed "Design Decisions" and was unslotted, so the ceiling could not see it.
        if (n ~ / design /)                              return "5"
        return ""
      }

      # Record a section on first use, preserving document order. A heading registers
      # eagerly, so a section the author declared but left without prose reports 0 rather
      # than vanishing — for §4 Architecture Overview, mostly a diagram, a missing row and
      # a zero row mean different things. "(preamble)" is synthetic and registers only if
      # it accumulates content.
      function register_section(s) {
        if (!(s in reg)) { nsec++; order[nsec] = s; halfwords[s] = 0; reg[s] = 0; seen[s] = 1 }
      }

      # --- design-field helpers (mechanism-proportionality) ----------------------

      # Record one design-field hit for the detail block. Locator carries no line number —
      # the code-reference rule forbids one into a planning document — so callers pass a
      # heading or the opening words of a bullet instead.
      function record_field_hit(where, loc, reason) {
        nfhit++
        fhit_sec[nfhit] = where
        fhit_loc[nfhit] = loc
        fhit_reason[nfhit] = reason
      }

      # Close the currently open §7 option block, if any, scoring it against the flowchart
      # in §5.3: no Cost line warns (COST); Cost present but Misses absent or empty blocks
      # (MISSES). A block carrying Misses and no Cost warns on the same branch as one
      # carrying neither — the missing half is the declared price, so Cost absence is
      # checked first and short-circuits the Misses check. Only opt_open resets here — the
      # per-block fields reset when the NEXT block opens (H3 branch), which is the one reset
      # that matters: leaving it here too would let it silently cover for a dropped open-time
      # reset, so a later block would never inherit a still-true opt_cost/opt_miss_val from a
      # sibling that never re-declared them.
      function close_opt_block() {
        if (!opt_open) return
        if (!opt_cost) {
          COST++
          record_field_hit(sec, opt_loc, "no Cost: line in this option block")
        } else if (!opt_miss_val) {
          MISSES++
          record_field_hit(sec, opt_loc, "no Misses: value in this option block")
        }
        opt_open = 0
      }

      # A slot-7 section that closes having opened no ### option block warns once — this is
      # the silent-pass hole for a §7 whose options are bold lines or H4s, or omit the word
      # "Option" in their heading. Gated on the section actually being slot 7: a document
      # that never entered §7 at all must not warn from here (that is absence, not this).
      function close_slot7_section() {
        if (canon(sec) == "7" && !slot7_block_ever) {
          COST++
          record_field_hit(sec, sec, "no ### option block opened in this section")
        }
        slot7_block_ever = 0
      }

      # Slot 3 has no section-level "no group opened" counterpart to close_slot7_section()
      # above. D3: an earlier version fired that warning at section close, gated on "no fully-
      # valid group ever opened in this section" — which went silent the instant ANY valid
      # group appeared earlier in the same section (a later malformed opener became invisible),
      # and fired on ANY bullet at all, valid-group-related or not (a §3 holding only
      # **Context Files:** or **Verification:** bullets warned despite attempting no
      # requirement group whatsoever). Both were section-scoped proxies for a fact each
      # malformed shape already knows about itself the instant it is seen: the heading-level
      # opener (H3+ heading rule, below) and the bulleted-label opener (field_scan, below) now
      # report there directly — the same standing the spaced-colon near-miss already had —
      # independent of slot state and of each other, so a malformed opener warns once wherever
      # it appears, no matter what else is or is not in the section around it.
      function close_slot3_section() {
        req_close_loc = ""
      }

      # First 6 words of a requirement bullet, list marker stripped for readability only —
      # this is display, not a scan input. Never digit-only in practice, since the code-
      # reference rule forbids a bare line-number locator and this is prose words instead.
      function opening_words(raw,   t, w, n, i, out) {
        t = raw
        sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", t)
        n = split(t, w, /[ \t]+/)
        out = ""
        for (i = 1; i <= n && i <= 6; i++) out = out (out == "" ? "" : " ") w[i]
        return out
      }

      # D8: the ONE place that knows how much padding **Label:** tolerates, at the label
      # itself and at the line own edges — mirroring markdown_parser.py exactly: FIELD_PATTERN
      # (^\*\*(?P<name>[^*]+):\*\*...) matched against line.strip(), then
      # match.group("name").strip(). Given a raw line, returns the field name it opens with —
      # one of the three requirement-group names, "From", some other label, or "" if the line
      # does not open with **...:** at all. D5 widened the near-miss branch for the three
      # requirement labels; D7 widened it again for wide Unicode whitespace; this round found
      # the identical axis unfixed at the From: label, because each site kept its own
      # spelling-tolerant regex instead of asking one function. Wide-whitespace (NBSP, the
      # U+2000-U+200A block, \v, \f) is folded to a plain space FIRST, both at the line edges
      # and around the label, in the SAME gsub — Python str.strip() does not distinguish the
      # two either. Every site below that needs to know "does this line open with a
      # **Label:**, and if so which" calls this instead of keeping its own regex, so fixing
      # one label spelling and missing another stops being possible.
      function field_label(line,   t) {
        t = line
        gsub(/\302\240|\342\200[\200-\212]|\013|\014/, " ", t)
        gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t !~ /^\*\*[^*]+:\*\*/) return ""
        sub(/^\*\*[ \t]*/, "", t)
        sub(/[ \t]*:\*\*.*$/, "", t)
        return t
      }

      # Validate a From: tag value: the first whitespace-delimited token, and the second
      # where the first demands one. Text beyond that is free prose (§5.3) — a tag may carry
      # a ticket link or an explanatory clause, so only the first two tokens are tested. D4:
      # first is looked up in from_kind[], built once in BEGIN from a single declared literal
      # — never compared with == against a token spelled out here, and never tested with ~
      # against anything: the only regex match in this function is w[2] against the date
      # format, which tests the SECOND token shape, not whether the first is accepted. An
      # unrecognised first token reads kind as "" (see the BEGIN comment) and falls through
      # every branch below to the trailing return 0.
      function from_valid(value,   w, n, first, kind) {
        gsub(/^[ \t]+/, "", value)
        n = split(value, w, /[ \t]+/)
        if (n < 1) return 0
        first = w[1]
        kind = from_kind[first]
        if (kind == "bare") return 1
        if (kind == "value") return (n >= 2 && w[2] != "")
        if (kind == "date") return (n >= 2 && w[2] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
        return 0
      }

      # Strip one leading blockquote marker run, list marker, and table pipe from a slot-7
      # field line before testing the Cost:/Misses: anchor (M1) — a block declaring both
      # fields as list items, blockquote lines, or table cells otherwise never matches, and
      # close_opt_block() then reports the value as absent even though it is present. Slot 3
      # cannot reuse this: stripping there would let a bullet-line bold label pass for a
      # group opener (see field_scan below), which is exactly the hazard the raw line guards
      # against. Order matters only in that each sub() is a no-op when its prefix is absent,
      # so a line carrying none, one, or several of these prefixes strips cleanly either way.
      function strip_field_prefix(s) {
        sub(/^([ \t]*>)+[ \t]*/, "", s)
        sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", s)
        sub(/^[ \t]*\|[ \t]*/, "", s)
        return s
      }

      # The presence check (mechanism-proportionality). Called from the table-row and prose
      # branches with the RAW line — never the marker-stripped text those branches build for
      # their own word count, because stripping the list marker puts a bold label that opens
      # a bullet at position 0, where the line-start test below would misread it as a group
      # opener or a misplaced From: tag. Both branches sit below `fence { next }`, so a
      # fenced example is exempt without any special-casing here.
      function field_scan(raw, where,   slot, val, occ, n, i, misplaced, pfx, was_req,
                           bulleted_open, ncell, cell, ci, cv, nv, pv, lbl, blbl, nbraw) {
        slot = canon(where)
        if (slot == "7") {
          if (opt_open) {
            # D6: a table row is scanned PER CELL, not just cell 1. A single first-pipe strip
            # (below, in the non-table branch) anchors the label test at line start, so it can
            # only ever see whichever field happens to open the FIRST cell — a Cost: and
            # Misses: label sharing one row ("| **Cost:** ~1 LOC | **Misses:** none |") or a
            # label-row/value-row layout ("| **Cost:** | **Misses:** |" over "| ~1 LOC | none
            # |") both left the SECOND field invisible; the D1/D2 value-side fix could not
            # rescue this, since it runs after the anchor and the anchor itself never matched.
            # Splitting the row on its own pipes and testing each cell independently closes the
            # position dimension entirely — this is not one more shape added to the list
            # (bold mentions, indentation, list markers, trailing-space labels, two-column
            # cells, leading-space labels), it replaces "match the whole line once" with
            # "match every cell", which subsumes the cell-1 case as the N=1 instance of it.
            if (raw ~ /^([ \t]*>)*[ \t]*\|/) {
              # Split on the RAW line, unstripped — no strip_field_prefix() call needed here
              # (unlike the non-table branch below, which anchors ONE label at line start and
              # so does need its leading marker gone first). A blockquote marker or the row
              # own opening pipe just becomes an extra leading cell that never matches either
              # label pattern; every cell is tested on its own, so it costs nothing to carry.
              ncell = split(raw, cell, /\|/)
              # D6 cross-row: a label-row/value-row layout puts the Misses LABEL in one row
              # and its value in the SAME COLUMN of the very next table row — a shape no
              # single row can resolve alone. miss_pending_col, armed below once the OWN cells
              # of a row are exhausted with no value found, is resolved here FIRST, against
              # the current row cell at that remembered column, before the current row own
              # labels are scanned. Bounded to exactly one row of lookahead — cleared whether
              # it resolves or not — so a later, unrelated table sharing the same option block
              # cannot be mistaken for the missing value.
              if (miss_pending_col > 0) {
                if (miss_pending_col <= ncell) {
                  pv = cell[miss_pending_col]
                  gsub(/^[ \t]+|[ \t]+$/, "", pv)
                  if (pv != "" && pv !~ /^\*\*(Cost|Misses):\*\*/) opt_miss_val = 1
                }
                miss_pending_col = 0
              }
              for (ci = 1; ci <= ncell; ci++) {
                cv = cell[ci]
                gsub(/^[ \t]+|[ \t]+$/, "", cv)
                # Anchored at CELL start — matching anywhere in the cell let a bold MENTION in
                # Pros/Cons prose (e.g. "reuses the existing **Cost:** tracking") satisfy or
                # spoof the gate (H1a/H1b), the same reasoning the non-table anchor below uses.
                if (cv ~ /^\*\*Cost:\*\*/) opt_cost = 1
                if (cv ~ /^\*\*Misses:\*\*/) {
                  val = cv
                  sub(/^\*\*Misses:\*\*/, "", val)
                  gsub(/^[ \t]+|[ \t]+$/, "", val)
                  # The D1 two-column shape: the label sits ALONE in its own cell and the value
                  # is the ADJACENT cell ("| **Misses:** | none |") — look there only when
                  # this cell own value is empty, and only when that next cell is not itself a
                  # recognised label: a Misses cell immediately followed by a Cost cell
                  # ("| **Misses:** | **Cost:** ~5 |", both label-only) must still read as an
                  # EMPTY Misses, not slurp the whole Cost cell as if it were the Misses value.
                  if (val == "" && ci + 1 <= ncell) {
                    nv = cell[ci + 1]
                    gsub(/^[ \t]+|[ \t]+$/, "", nv)
                    if (nv !~ /^\*\*(Cost|Misses):\*\*/) val = nv
                  }
                  if (val != "") opt_miss_val = 1
                  else miss_pending_col = ci
                }
              }
            } else {
              # Non-table forms (plain, list, blockquote): a single label per line, anchored
              # at line start (optional leading whitespace) after strip_field_prefix removes
              # any list/blockquote marker (M1) — slot 3 keeps the raw line instead, because a
              # stripped list marker there would put a bold label at position 0, where the
              # group-opener test would misread it (§5.3), a hazard slot 7 does not have.
              pfx = strip_field_prefix(raw)
              if (match(pfx, /^[ \t]*\*\*Cost:\*\*/)) opt_cost = 1
              if (match(pfx, /^[ \t]*\*\*Misses:\*\*/)) {
                val = pfx
                sub(/^.*\*\*Misses:\*\*/, "", val)
                # D2: a pipe here is document content, never a cell boundary (this branch only
                # runs when raw is NOT a table row), so the value is read to the end of the
                # line with no realignment.
                gsub(/^[ \t]+|[ \t]+$/, "", val)
                if (val != "") opt_miss_val = 1
              }
            }
          }
          return
        }
        if (slot != "3") return

        # A bold label at line start is a group opener — but only three labels open a
        # SCANNED (requirement) group. Any other label at line start, or **From:** itself,
        # opens a group this scan does not treat as an opener: **From:** is a per-bullet
        # tag, not a section boundary, and the C2 Context Files carve-out falls out of this
        # mechanism rather than needing a special case. A bold span NOT at line start (a
        # mid-bullet `**Cost:**` mention, as FR-1 itself carries) never changes req_group.
        # "Line start" allows optional leading whitespace: the _collect_bullets helper in
        # markdown_parser.py strips whitespace before testing FIELD_PATTERN, so an indented
        # label still breaks the parser while escaping an unindented-only scanner (H6). No
        # apostrophe in a comment below this point in the awk program: the whole program is a
        # single-quoted shell string and a literal apostrophe would end it early.
        # was_req remembers whether THIS line found the group already open, before any of the
        # branches below can change it — the only fact M3 needs to attribute a closure to the
        # label that caused it, rather than to whatever bullet happens to follow.
        was_req = (req_group == "req")
        # D8: the one normalisation every label site below decides from — see field_label()
        # above. lbl is what THIS raw line opens with, if anything: one of the three
        # requirement-group names, "From", some other label entirely, or "" if the line does
        # not open with **...:** at all. D5 widened the near-miss branch for the three
        # requirement labels; D7 (an internal round) widened it again for wide Unicode
        # whitespace; this round found the identical axis unfixed at the From: label, because
        # each site kept its own spelling-tolerant regex instead of asking one function.
        lbl = field_label(raw)
        # nbraw: wide-whitespace bytes (NBSP, the U+2000-U+200A block, \v, \f) folded to a
        # plain space — for the occurrence split below. An INLINE **From:** tag can carry the
        # same padding a line-opening one can ("- FR-1: alpha \xe2\x80\x94 **From :** hunch"),
        # and split() needs the text pre-normalised so its own [ \t]* delimiter sees every
        # occurrence, not just the ASCII-padded ones.
        nbraw = raw
        gsub(/\302\240|\342\200[\200-\212]|\013|\014/, " ", nbraw)
        # bulleted_open (D3, widened D8): a list marker directly in front of the bold label —
        # "- **Functional Requirements:**" — fails field_label() too (it requires ** at line
        # start, no marker) so req_group never changes and, unguarded, the line would fall
        # straight through to the plain per-bullet "no From: tag" check at the bottom, which
        # cannot tell "this bullet IS the malformed opener" from "this bullet lacks a tag" and
        # would report the wrong reason. Reported here instead, once, the instant it is seen —
        # the same standing as the near-miss opener below, independent of req_group/section
        # state and of whatever else the section does or does not contain (D3). The label
        # itself is read through field_label() (D8) after stripping the marker, so a padded
        # bulleted opener ("- ** Functional Requirements:**") is not left as a ninth hole.
        bulleted_open = 0
        if (raw ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]+\*\*/) {
          blbl = raw
          sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", blbl)
          blbl = field_label(blbl)
          if (blbl == "Functional Requirements" || blbl == "Non-Functional Requirements" || blbl == "Constraints") \
            bulleted_open = 1
        }
        if (bulleted_open) {
          UNTAGGED++
          record_field_hit(where, opening_words(raw), \
              "requirement group opener is a bulleted label, not inline bold text; the FIELD_PATTERN in markdown_parser.py does not match a list marker before it")
        }
        if (raw ~ /^[ \t]*\*\*(Functional Requirements|Non-Functional Requirements|Constraints):\*\*/) {
          req_group = "req"
          req_scan_bullets = 1
          req_close_loc = ""
        } else if (lbl == "Functional Requirements" || lbl == "Non-Functional Requirements" || lbl == "Constraints") {
          # D5/D7/D8: any padding at all around the label — [ \t], or the wide Unicode
          # whitespace D7 added — reaches here through field_label() (D8) once the EXACT,
          # zero-padding form immediately above has already failed to match. markdown_parser.py
          # FIELD_PATTERN plus name.strip() collects this as a real requirement group in
          # production — codex-flow receives its bullets as genuine requirements — so
          # req_group becomes "req", the same state a valid opener sets, and an inline From:
          # tag on a bullet beneath it is scored as inside-a-group rather than misplaced (the
          # false FROM: blocker this fix removes). This opener is ALSO reported below,
          # unconditionally (D3: independent of whether a valid group exists elsewhere in the
          # section), so its own hit already tells the author where to look. What does NOT
          # carry over is req_scan_bullets: it stays 0, so a bullet beneath the near-miss
          # opener with no tag at all is not individually flagged too — scoring every bullet
          # beneath it would scale the same defect by bullet count instead of stating it once.
          req_group = "req"
          req_scan_bullets = 0
          req_close_loc = ""
          UNTAGGED++
          record_field_hit(where, opening_words(raw), \
              "requirement group opener has whitespace around the label inside **...**; markdown_parser.py accepts it but this scanner does not check bullets beneath it for a missing From: tag")
        } else if (lbl == "From") {
          # misplaced — handled as occurrence 1 below; group state unchanged.
        } else if (lbl != "") {
          req_group = "other"
          req_scan_bullets = 0
          if (was_req) req_close_loc = opening_words(raw)
        }

        # Every bold From: occurrence on the line is validated independently — no first-match
        # or last-match rule (U17). split() on the padding-tolerant label (D8) yields one
        # piece of trailing text per occurrence, correctly scoped between consecutive
        # occurrences, over nbraw so an inline occurrence padded with wide whitespace is found
        # the same as an ASCII-padded or exact one.
        n = split(nbraw, occ, /\*\*[ \t]*From[ \t]*:\*\*/)
        for (i = 2; i <= n; i++) {
          val = occ[i]
          misplaced = ((i == 2) && (lbl == "From")) || (req_group != "req")
          if (misplaced) {
            FROM++
            if ((i == 2) && (lbl == "From")) {
              record_field_hit(where, opening_words(raw), "From: label opens the line — must be inline (C3)")
            } else if (req_close_loc != "") {
              # M3: the tag is genuinely outside the requirement group — that firing is
              # correct, the bullet really did vanish from _collect_bullets() — but the group
              # was closed by an earlier bold label, not by this bullet, so the hit is
              # recorded against that label. Pointing at the tagged bullet instead reads as
              # "strip this tag", which is the wrong fix.
              record_field_hit(where, req_close_loc, "requirement group closed by this label; a From: tag below it is outside the group")
            } else {
              record_field_hit(where, opening_words(raw), "From: label outside a requirement group")
            }
          } else if (!from_valid(val)) {
            FROM++
            record_field_hit(where, opening_words(raw), "unrecognised or incomplete From: value")
          }
        }

        # A requirement bullet with no From: tag at all — independent of the validation
        # above, since an invalid or misplaced tag still counts as "has a tag" here. Gated on
        # req_scan_bullets, not req_group == "req" directly (H1): both a valid opener and the
        # near-miss set req_group to "req" so From: validation treats them alike, but only
        # the valid opener also sets req_scan_bullets, so a bullet beneath the near-miss is
        # not individually flagged here. Also excludes bulleted_open (D3): that line IS the
        # malformed opener, already reported above under its own reason — an unclosed valid
        # group from earlier in the section can leave req_scan_bullets true here too, and
        # without this exclusion the same line would be double-counted a second time as an
        # untagged bullet instead. D8 (the reviewer pairing constraint): reuses n from the
        # split above (n <= 1 means no occurrence at all was found) rather than a second,
        # separately-spelled presence test — two independent tests for "does a From: tag
        # exist here" can disagree on a padded tag (one recognising it, the other not),
        # double-counting the same bullet as both invalid AND untagged; reusing the same
        # split result makes that impossible by construction.
        if (req_scan_bullets && !bulleted_open && raw ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]/) {
          if (n <= 1) {
            UNTAGGED++
            record_field_hit(where, opening_words(raw), "requirement bullet with no From: tag")
          }
        }
      }

      # Two sections with the same heading text would merge into one row and misreport the
      # profile, so the repeat gets a suffix. "TOTAL" is reserved in BEGIN for the same
      # reason: a section by that name would collide with the summary row.
      function unique(h,   n, cand) {
        if (!(h in seen)) return h
        n = 2
        cand = h " (" n ")"
        while (cand in seen) { n++; cand = h " (" n ")" }
        return cand
      }

      # A window of whole words around the match, locating the hit without a line number —
      # which the code-reference rule forbids into a planning document. Punctuation-only
      # tokens are kept so the window can be grepped against the source.
      function window(i, nn,   lo, hi, j, out) {
        lo = i - 5; if (lo < 1) lo = 1
        hi = i + 7; if (hi > nn) hi = nn
        out = ""
        for (j = lo; j <= hi; j++) out = out (out == "" ? "" : " ") ow[j]
        if (lo > 1) out = "..." out
        if (hi < nn) out = out "..."
        return out
      }
    ' "$f" 2>&1)
    rc=$?
    printf '%s\n' "$OUT"
    if [ $rc -ne 0 ]; then
        echo failed >> "$STATUS"
    elif ! grep -q '^TOTAL[ 	]' <<<"$OUT"; then
        # An interpreter that exits 0 without emitting a table has not measured anything.
        # `command -v` cannot catch this: /bin/echo and /bin/true both pass it.
        #
        # A `printf | grep -q` PIPE here (M3) misdiagnoses a real, valid measurement as this
        # same failure: TOTAL prints early and grep -q exits the instant it matches, and once
        # the design-field detail block that follows pushes the remainder past the 64 KiB pipe
        # buffer, the still-writing printf gets SIGPIPE — 141 under `set -o pipefail` above —
        # which this `!` then reads as "no table". A here-string has no live writer to signal:
        # bash spools it to a temp file before grep ever starts, so grep exiting early is inert.
        echo notable >> "$STATUS"
    fi
done

if [ -s "$STATUS" ]; then
    echo "BLOCKER: $AWK produced no usable measurement for $(wc -l < "$STATUS") file(s)" >&2
    exit 1
fi
exit 0
