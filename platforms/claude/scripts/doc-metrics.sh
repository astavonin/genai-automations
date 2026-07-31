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
      /^###+[ \t]/ {
        scan_register(heading_text($0), sec)
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
    elif ! printf '%s' "$OUT" | grep -q '^TOTAL[ 	]'; then
        # An interpreter that exits 0 without emitting a table has not measured anything.
        # `command -v` cannot catch this: /bin/echo and /bin/true both pass it.
        echo notable >> "$STATUS"
    fi
done

if [ -s "$STATUS" ]; then
    echo "BLOCKER: $AWK produced no usable measurement for $(wc -l < "$STATUS") file(s)" >&2
    exit 1
fi
exit 0
