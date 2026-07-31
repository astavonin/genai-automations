#!/usr/bin/env bash
# citation-scan.sh — list candidate line-number citations in an issue folder's Markdown.
#
# Enforces the code-reference rule in ~/.claude/CLAUDE.md → Markdown Writing → code
# references: a line number is durable only when pinned to a pushed commit, and a
# planning document is never cited by line.
#
# The output is a CANDIDATE LIST, not a verdict. Two exemptions are resolved here
# mechanically (fenced blocks, hash-pinned permalinks) and one is approximated
# (a line number accompanying a named symbol is permitted, reported as "accompanied ok").
# Everything else is triaged by the reading agent.
#
# Usage:   citation-scan.sh <issue-folder>
#
# Exit codes:
#   0  scan ran — hits may or may not be present; read the output
#   1  BLOCKER — bad input (unresolved path, placeholder, no .md files)
#
# Exit status does NOT signal "hits found", so callers must read the output rather than
# wiring && to it. A hit is frequently a permitted accompaniment.
#
# Tests: tests/verify-citation-scan.sh in the genai-automations repo (not installed alongside
#        this script; run it there after editing).

set -uo pipefail

# Interpreter seam. gawk and mawk disagree on regex features, and /usr/bin/awk is an
# alternatives symlink, so the test corpus runs this script once per available awk.
AWK="${CITATION_SCAN_AWK:-awk}"
if ! command -v "$AWK" >/dev/null 2>&1; then
    echo "BLOCKER: awk interpreter not found: $AWK" >&2
    exit 1
fi

ISSUE_FOLDER="${1-}"

if [ -z "$ISSUE_FOLDER" ]; then
    echo "BLOCKER: no issue folder given — resolve it first (see issue-folder-resolve/SKILL.md)" >&2
    exit 1
fi
case "$ISSUE_FOLDER" in
    *"<"*) echo "BLOCKER: placeholder left in path — $ISSUE_FOLDER" >&2; exit 1 ;;
esac
if [ ! -d "$ISSUE_FOLDER" ]; then
    echo "BLOCKER: not a directory — $ISSUE_FOLDER" >&2
    exit 1
fi

FOUND=$(find "$ISSUE_FOLDER" -maxdepth 1 -name '*.md' -type f | sort)
if [ -z "$FOUND" ]; then
    echo "BLOCKER: no .md files under $ISSUE_FOLDER — confirm the path is the one the writer used" >&2
    exit 1
fi

AWK_STATUS=$(mktemp)
trap 'rm -f "$AWK_STATUS"' EXIT

HITS=$(printf '%s\n' "$FOUND" | while IFS= read -r f; do
    "$AWK" -v F="$f" '
      # Strip CR so CRLF files tokenise like LF ones.
      { sub(/\r$/, "") }

      # Fenced-output exemption. Track the delimiter so a ``` block nested inside a
      # ~~~markdown block does not close the outer one — the shape DESIGN-TEMPLATE
      # mandates for pasting an observed-failure ledger.
      /^[ \t]*(```|~~~)/ {
        d = ($0 ~ /~~~/) ? "~~~" : "```"
        if (!fence) { fence = 1; delim = d } else if (d == delim) { fence = 0 }
        next
      }
      fence { next }

      {
        line = $0
        # Snippet-annotation exemption: drop hash-pinned permalinks, label and URL
        # together — the label text is itself a bare locator and survives a URL-only
        # strip. Seven explicit hex classes, not {7,40}: mawk silently ignores interval
        # quantifiers, and a looser bound would accept branch refs such as /blob/dev/
        # or /blob/cafe/ as though they were commits.
        gsub(/\[[^]]*\]\([^)]*\/blob\/[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]+\/[^)]*\)/, " ", line)
        gsub(/https?:\/\/[^ )]*/, " ", line)

        # A line number accompanying a named symbol is permitted. Approximated by
        # looking for a symbol-shaped token anywhere on the line.
        hassym = (line ~ /`[^`]*\(\)`/ || line ~ /`[^`]*::[^`]*`/ || line ~ /→/)

        # Emit from backticked spans, blanking each so the unbackticked pass cannot
        # re-scan its interior and report the inner path of a pinned locator.
        bare = line
        while (match(bare, /`+[^`]+`+/)) {
          span = substr(bare, RSTART, RLENGTH)
          bare = substr(bare, 1, RSTART - 1) " " substr(bare, RSTART + RLENGTH)
          gsub(/`/, " ", span)
          # Scan the span interior rather than testing it as one token, so a locator that
          # is not the final word of the span is still seen. The optional hex-prefix group is
          # load-bearing: without it the interior scan matches the path alone and a pinned
          # locator loses its pin, reporting as unpinned.
          while (match(span, /([0-9a-fA-F]+:)?[A-Za-z0-9_.\/@-]+:[0-9]+(-[0-9]+)?/)) {
            emit(substr(span, RSTART, RLENGTH))
            span = substr(span, RSTART + RLENGTH)
          }
        }
        while (match(bare, /([0-9a-fA-F]+:)?[A-Za-z0-9_.\/@-]+:[0-9]+(-[0-9]+)?/)) {
          emit(substr(bare, RSTART, RLENGTH))
          bare = substr(bare, RSTART + RLENGTH)
        }
      }

      END {
        # An unclosed fence hides every following line, so a clean result would be a lie.
        # BLOCKs rather than warning, matching doc-metrics.sh: a warning on stdout with no
        # BLOCKER token was invisible to every caller convention in this config.
        if (fence) {
          printf "BLOCKER: unclosed %s fence in %s — lines after it were not scanned.\n", delim, F > "/dev/stderr"
          exit 1
        }
      }

      function emit(tok,   target, pinned, pfx) {
        if (tok !~ /:[0-9]+(-[0-9]+)?$/) return
        pfx = substr(tok, 1, index(tok, ":") - 1)
        pinned = (pfx ~ /^[0-9a-fA-F]+$/ && length(pfx) >= 7 && length(pfx) <= 40)
        target = tok
        if (pinned) target = substr(tok, index(tok, ":") + 1)
        # Path-shaped only: a separator, a letter-initial extension, or a known
        # extensionless build file. The extension must start with a letter so a prose
        # ratio like 3.5:1 is not read as a locator.
        if (target !~ /\// && target !~ /\.[A-Za-z][A-Za-z0-9]*:/ &&
            toupper(target) !~ /^(MAKEFILE|GNUMAKEFILE|DOCKERFILE|CMAKELISTS|JENKINSFILE|RAKEFILE|GEMFILE|VAGRANTFILE|JUSTFILE|PROCFILE|BUILD|WORKSPACE|KCONFIG):/) return
        # Planning docs take no line number in any form — a prepended hash does not
        # license one, and neither does an accompanying symbol.
        if (target ~ /\.md:[0-9]/) { print F ":" FNR ":  planning-doc ref   " tok; return }
        if (pinned) return
        if (hassym) { print F ":" FNR ":  accompanied ok     " tok; return }
        print F ":" FNR ":  unpinned source   " tok
      }
    ' "$f" || echo failed >> "$AWK_STATUS"
done)

if [ -s "$AWK_STATUS" ]; then
    echo "BLOCKER: $AWK failed on $(wc -l < "$AWK_STATUS") file(s) — result is not clean" >&2
    exit 1
fi

if [ -z "$HITS" ]; then
    echo "clean: no candidate line-number citations"
else
    printf '%s\n' "$HITS"
    echo "--- 'unpinned source' and 'planning-doc ref' are defects unless exempt;"
    echo "--- 'accompanied ok' is permitted (symbol present) and needs no action."
fi
exit 0
