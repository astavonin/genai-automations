#!/usr/bin/env bash
# review-pack.sh — concatenate a caller-supplied file list into one bundle, one path
# header per file, and print the bundle's absolute path, line count and byte count.
#
# `lines` and `bytes` are read back from the written file, never summed from the inputs,
# so a figure this script did not measure can never reach a caller (incident 2026-07-30).
#
# Usage:   review-pack.sh <out-path> <file>…
#
# Exit codes:
#   0  the bundle is written and the printed line describes it
#   1  BLOCKER on stderr, nothing on stdout
#
# The printed line's last field is always the byte count, so a caller reads it with
# `awk '{print $NF}'` rather than matching the middle-dot separator.
#
# Tests: tests/verify-review-pack.sh in the genai-automations repo (not installed alongside
#        this script; run it there after editing).

set -u

MARKER='===== review-pack: '

blocker() { printf 'BLOCKER: %s\n' "$1" >&2; exit 1; }

[ "$#" -ge 2 ] || blocker "no input file — an output path and at least one file path are required"
OUT="$1"; shift

# An empty argument resolves silently (realpath -m "" prints nothing, rc 0) and would write a stray .partial into the caller's cwd.
for arg in "$OUT" "$@"; do
    [ -n "$arg" ] || blocker "empty argument — an out-path and every file path must be non-empty"
    [[ "$arg" =~ \<[A-Za-z0-9_-]+\> ]] && blocker "unsubstituted placeholder — $arg"
done
for arg in "$OUT" "$@"; do
    case "$arg" in
        *$'\n'*) blocker "newline in argument — ${arg//$'\n'/\\n}" ;;
    esac
done

# realpath -m needs no existing path, so this gate runs before the removal and before any input check.
resolve() { realpath -m -- "$1"; }

PARTIAL="$OUT.partial"
out_r=$(resolve "$OUT") || blocker "could not resolve out-path — $OUT"
[ -n "$out_r" ] || blocker "could not resolve out-path — $OUT"
partial_r=$(resolve "$PARTIAL") || blocker "could not resolve out-path's .partial sibling — $PARTIAL"
[ -n "$partial_r" ] || blocker "could not resolve out-path's .partial sibling — $PARTIAL"
for f in "$@"; do
    f_r=$(resolve "$f") || blocker "could not resolve input path — $f"
    [ -n "$f_r" ] || blocker "could not resolve input path — $f"
    if [ "$f_r" = "$out_r" ]; then
        blocker "out-path resolves to an input — '$OUT' and '$f' both resolve to '$out_r'"
    fi
    if [ "$f_r" = "$partial_r" ]; then
        blocker "out-path's .partial sibling resolves to an input — '$PARTIAL' and '$f' both resolve to '$partial_r'"
    fi
done

# -f alone (no -r) exits 1 on a directory, which is the BLOCKER this step needs.
rm -f -- "$OUT" || blocker "could not remove out-path — $OUT; whatever was there survives"

for f in "$@"; do
    if [ ! -e "$f" ]; then
        blocker "path does not exist — $f"
    elif [ ! -f "$f" ]; then
        blocker "path is not a regular file — $f"
    elif [ ! -r "$f" ]; then
        blocker "path is not readable — $f"
    fi
done

# Anchored at column 0 so an indented marker is content; grep's exit 2 is a read error, never a miss.
for f in "$@"; do
    hit=$(grep -n -m1 "^$MARKER" -- "$f")
    grep_rc=$?
    if [ "$grep_rc" -eq 0 ]; then
        blocker "input carries header marker at column 0 — $f:${hit%%:*}"
    elif [ "$grep_rc" -ne 1 ]; then
        blocker "could not scan for header marker — $f"
    fi
done

# Truncates any .partial left by an earlier failed run — the packer holds no state
# between runs, so stale bytes here must never leak into this run's bundle.
: > "$PARTIAL" || blocker "could not open for writing — $PARTIAL"

not_first=0
for f in "$@"; do
    {
        { [ "$not_first" -eq 0 ] || printf '\n'; } &&
            printf '%s%s =====\n' "$MARKER" "$f" &&
            cat -- "$f"
    } >> "$PARTIAL" || blocker "write failed — $PARTIAL ($f)"
    not_first=1
done

lines=$(awk 'END{print NR}' < "$PARTIAL") || blocker "read-back failed — $PARTIAL"
bytes=$(wc -c < "$PARTIAL") || blocker "read-back failed — $PARTIAL"

mv -f -- "$PARTIAL" "$OUT" || blocker "move failed — $PARTIAL $OUT"

# Resolved after the move: rm -f unlinked a symlink $OUT and mv recreated it, so the earlier resolution names the wrong file.
printed_path=$(resolve "$OUT") || blocker "could not resolve out-path after the move — $OUT"
[ -n "$printed_path" ] || blocker "could not resolve out-path after the move — $OUT"

printf 'bundle: %s · lines: %s · bytes: %s\n' "$printed_path" "$lines" "$bytes" || exit 1
