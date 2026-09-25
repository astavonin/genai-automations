#!/usr/bin/env bash
# verify-review-pack.sh — regression tests for platforms/claude/scripts/review-pack.sh
#
# One fixture tree per case, the real script invoked, the class of the result asserted —
# same shape as tests/verify-citation-scan.sh. Cases follow design.md §6 in order: guards
# first (each a BLOCKER the script must raise), then the success-path contract.
#
# Marker fixtures build the header line from the script's own MARKER value at run time
# rather than writing it literally at column 0 in this file's source — otherwise this
# suite would be unpackable by the packer it tests. See design.md §6's fixture rule.
#
# Do not run as root: several cases below depend on permission bits (read bit, write bit)
# being honoured, which root ignores.
#
# Exit codes: 0 = all tests passed, 1 = one or more failed.

set -uo pipefail

# Permission-bit cases (read bit, write bit) below are meaningless under root, which
# ignores them — they would false-pass rather than exercise the guard they test.
[ "$(id -u)" -eq 0 ] && { echo "SKIP: do not run this suite as root — it depends on permission bits root ignores"; exit 1; }

GREP=/usr/bin/grep
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/platforms/claude/scripts/review-pack.sh"

# Resolved once so every $d is already realpath-stable — an unresolved mktemp root under a
# symlinked TMPDIR (macOS /tmp -> /private/tmp) would false-red the "prints as absolute" case.
TMPDIR_ROOT=$(mktemp -d)
TMPDIR_ROOT=$(realpath "$TMPDIR_ROOT")
PASS=0
FAIL=0
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }

newdir() {   # $1: case name -> fresh fixture dir under TMPDIR_ROOT
    local d
    d="$TMPDIR_ROOT/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')"
    mkdir -p "$d"
    printf '%s' "$d"
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

# Captures stdout/stderr/exit status into globals for every assertion below to share, stdin
# pinned to /dev/null so a stdin-reading regression (M4) fails fast rather than hangs.
ERRFILE="$TMPDIR_ROOT/.stderr"
run() {
    STDOUT=$(bash "$SCRIPT" "$@" < /dev/null 2>"$ERRFILE")
    RC=$?
    STDERR=$(cat "$ERRFILE")
}

echo "review-pack.sh regression corpus"
echo "script: $SCRIPT"
[ -x "$SCRIPT" ] || { echo "  FAIL: script not executable"; exit 1; }

# The marker check is anchored at column 0 of a packed file's content, not of this file's
# own source — reading it back off the script under test is what keeps that value single-sourced.
MARKER=$(sed -n "s/^MARKER='\(.*\)'$/\1/p" "$SCRIPT")
[ -n "$MARKER" ] || { echo "  FAIL: could not extract MARKER from $SCRIPT"; exit 1; }

echo "== guards =="

# 1: arity — zero args, and an out-path with no file paths.
run
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -q 'BLOCKER' \
    && pass "no arguments at all — BLOCKER, exit 1, nothing on stdout" \
    || fail "no arguments at all — BLOCKER, exit 1, nothing on stdout" "rc=$RC stdout=$STDOUT stderr=$STDERR"

d=$(newdir arity_out_only)
run "$d/out.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -q 'BLOCKER' \
    && pass "output path with no file paths — BLOCKER, exit 1, nothing on stdout" \
    || fail "output path with no file paths — BLOCKER, exit 1, nothing on stdout" "rc=$RC stdout=$STDOUT stderr=$STDERR"

# M8: an empty out-path resolves silently (realpath -m "" prints nothing, rc 0) and would
# otherwise write a stray .partial into this shell's own cwd rather than a named path.
d=$(newdir empty_outpath)
printf 'x\n' > "$d/a.txt"
( cd "$d" && bash "$SCRIPT" "" "a.txt" < /dev/null > "$TMPDIR_ROOT/.emptystdout" 2>"$ERRFILE" )
empty_rc=$?
empty_stdout=$(cat "$TMPDIR_ROOT/.emptystdout")
empty_stderr=$(cat "$ERRFILE")
[ "$empty_rc" -eq 1 ] && [ -z "$empty_stdout" ] && printf '%s' "$empty_stderr" | $GREP -qF 'BLOCKER: empty argument' && [ ! -e "$d/.partial" ] \
    && pass "an empty out-path argument — BLOCKER by name, no .partial created in the caller's cwd" \
    || fail "an empty out-path argument — BLOCKER by name, no .partial created in the caller's cwd" "rc=$empty_rc stdout=$empty_stdout stderr=$empty_stderr"

# 2: unsubstituted <placeholder> — in the output path, and in a file path. Anchored on the
# exact reason text, not a bare 'placeholder' keyword — a fixture dir named for the case would otherwise leak that word into a different BLOCKER's own path-echoing message.
d=$(newdir placeholder_outpath)
printf 'x\n' > "$d/a.txt"
run "$d/<out>.txt" "$d/a.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: unsubstituted placeholder' \
    && pass "unsubstituted placeholder in the output path — BLOCKER" \
    || fail "unsubstituted placeholder in the output path — BLOCKER" "rc=$RC stderr=$STDERR"

d=$(newdir placeholder_filepath)
printf 'x\n' > "$d/a.txt"
run "$d/out.txt" "$d/<a>.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: unsubstituted placeholder' \
    && pass "unsubstituted placeholder in a file path — BLOCKER" \
    || fail "unsubstituted placeholder in a file path — BLOCKER" "rc=$RC stderr=$STDERR"

# 3: a newline — in the output path, and in a file path. Same anchoring rationale as above.
d=$(newdir newline_outpath)
printf 'x\n' > "$d/a.txt"
nl_out="$d/$(printf 'ou\nt').txt"
run "$nl_out" "$d/a.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: newline in argument' \
    && pass "newline in the output path — BLOCKER, nothing on stdout" \
    || fail "newline in the output path — BLOCKER, nothing on stdout" "rc=$RC stdout=$STDOUT stderr=$STDERR"

d=$(newdir newline_filepath)
nl_file="$d/$(printf 'fi\nle').txt"
run "$d/out.txt" "$nl_file"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: newline in argument' \
    && pass "newline in a file path — BLOCKER, nothing on stdout" \
    || fail "newline in a file path — BLOCKER, nothing on stdout" "rc=$RC stdout=$STDOUT stderr=$STDERR"

# 4: aliasing — out-path == an input, by four different spellings of the collision.
# Anchored on the BLOCKER prefix plus the exact reason clause, for the same reason noted above.
d=$(newdir alias_exact)
printf 'unchanged\n' > "$d/a.txt"
before=$(sha "$d/a.txt")
run "$d/a.txt" "$d/a.txt" "$d/b.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: out-path resolves to an input' && [ "$(sha "$d/a.txt")" = "$before" ] \
    && pass "output path spelled exactly as one input — BLOCKER, input bytes unchanged" \
    || fail "output path spelled exactly as one input — BLOCKER, input bytes unchanged" "rc=$RC stderr=$STDERR"

d=$(newdir alias_relative)
printf 'unchanged\n' > "$d/a.txt"
before=$(sha "$d/a.txt")
run "$d/a.txt" "$d/./a.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: out-path resolves to an input' && [ "$(sha "$d/a.txt")" = "$before" ] \
    && pass "output path reaching an input by a relative spelling against an absolute one — BLOCKER, input bytes unchanged" \
    || fail "output path reaching an input by a relative spelling against an absolute one — BLOCKER, input bytes unchanged" "rc=$RC stderr=$STDERR"

d=$(newdir alias_symlink)
printf 'unchanged\n' > "$d/b.txt"
before=$(sha "$d/b.txt")
ln -s "$d/b.txt" "$d/outlink"
run "$d/outlink" "$d/b.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: out-path resolves to an input' && [ "$(sha "$d/b.txt")" = "$before" ] \
    && pass "output path reaching an input through a symlink — BLOCKER, input bytes unchanged" \
    || fail "output path reaching an input through a symlink — BLOCKER, input bytes unchanged" "rc=$RC stderr=$STDERR"

d=$(newdir alias_partial)
printf 'unchanged\n' > "$d/out.txt.partial"
before=$(sha "$d/out.txt.partial")
printf 'z\n' > "$d/z.txt"
run "$d/out.txt" "$d/z.txt" "$d/out.txt.partial"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF "BLOCKER: out-path's .partial sibling resolves to an input" && [ "$(sha "$d/out.txt.partial")" = "$before" ] \
    && pass "an input spelled as the .partial path the run would write through — BLOCKER, input bytes unchanged" \
    || fail "an input spelled as the .partial path the run would write through — BLOCKER, input bytes unchanged" "rc=$RC stderr=$STDERR"

# 5: exists / regular file / readable, each naming the offending path. Anchored on the path
# plus its own reason clause — the path alone could also match a later guard's message about that same path (e.g. a write failure).
d=$(newdir missing_input)
run "$d/out.txt" "$d/does-not-exist.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF "BLOCKER: path does not exist — $d/does-not-exist.txt" \
    && pass "a path that does not exist — BLOCKER naming the offending path" \
    || fail "a path that does not exist — BLOCKER naming the offending path" "rc=$RC stderr=$STDERR"

d=$(newdir dir_as_file)
mkdir -p "$d/subdir"
run "$d/out.txt" "$d/subdir"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF "BLOCKER: path is not a regular file — $d/subdir" \
    && pass "a directory passed as a file — BLOCKER naming the offending path" \
    || fail "a directory passed as a file — BLOCKER naming the offending path" "rc=$RC stderr=$STDERR"

d=$(newdir unreadable_input)
printf 'x\n' > "$d/secret.txt"
chmod 000 "$d/secret.txt"
run "$d/out.txt" "$d/secret.txt"
rc_unreadable="$RC"; stdout_unreadable="$STDOUT"; stderr_unreadable="$STDERR"
chmod 644 "$d/secret.txt"
[ "$rc_unreadable" -eq 1 ] && [ -z "$stdout_unreadable" ] && printf '%s' "$stderr_unreadable" | $GREP -qF "BLOCKER: path is not readable — $d/secret.txt" \
    && pass "a file with its read bit cleared — BLOCKER naming the offending path" \
    || fail "a file with its read bit cleared — BLOCKER naming the offending path" "rc=$rc_unreadable stderr=$stderr_unreadable"

# 6: output path in a directory that does not exist — reaches the .partial-creation guard,
# now asserted on its own BLOCKER text rather than shape alone.
d=$(newdir missing_outdir)
printf 'x\n' > "$d/a.txt"
run "$d/no-such-dir/out.txt" "$d/a.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF "BLOCKER: could not open for writing — $d/no-such-dir/out.txt.partial" \
    && pass "output path in a directory that does not exist — BLOCKER naming the .partial path, no printed line" \
    || fail "output path in a directory that does not exist — BLOCKER naming the .partial path, no printed line" "rc=$RC stdout=$STDOUT stderr=$STDERR"

# 7: forged header marker at column 0.
d=$(newdir marker_forged)
header_line="${MARKER}fake-source ====="
printf 'preamble\n%s\nrest\n' "$header_line" > "$d/forged.txt"
run "$d/out.txt" "$d/forged.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF "$d/forged.txt:2" && [ ! -e "$d/out.txt" ] \
    && pass "an input carrying the header marker at column 0 — BLOCKER naming path and line number, no file at the output path" \
    || fail "an input carrying the header marker at column 0 — BLOCKER naming path and line number, no file at the output path" "rc=$RC stderr=$STDERR"

# 8: a bundle left by an earlier run, this run BLOCKERing on an input deleted since.
d=$(newdir stale_bundle)
printf 'one\n' > "$d/a.txt"
printf 'two\n' > "$d/b.txt"
run "$d/out.txt" "$d/a.txt" "$d/b.txt"
first_rc="$RC"
rm -f "$d/b.txt"
run "$d/out.txt" "$d/a.txt" "$d/b.txt"
[ "$first_rc" -eq 0 ] && [ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && [ ! -e "$d/out.txt" ] \
    && pass "a bundle left by an earlier run, this run BLOCKERing on an input deleted since — no file at the output path afterwards" \
    || fail "a bundle left by an earlier run, this run BLOCKERing on an input deleted since — no file at the output path afterwards" "first_rc=$first_rc rc=$RC"

# 9: output path is an existing directory — rm -f exits 1.
d=$(newdir outpath_is_dir)
mkdir -p "$d/outdir"
printf 'keep\n' > "$d/outdir/marker.txt"
before=$(sha "$d/outdir/marker.txt")
printf 'x\n' > "$d/a.txt"
run "$d/outdir" "$d/a.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF "BLOCKER: could not remove out-path — $d/outdir;" && [ "$(sha "$d/outdir/marker.txt")" = "$before" ] \
    && pass "output path is an existing directory — BLOCKER naming it, no printed line, directory contents unchanged" \
    || fail "output path is an existing directory — BLOCKER naming it, no printed line, directory contents unchanged" "rc=$RC stdout=$STDOUT stderr=$STDERR"

# 10 (M1): the write bit blocks .partial creation itself — this never reaches the body-write
# loop, so the case is named for that, not "the first body write", which it never reaches.
d=$(newdir readonly_outdir)
mkdir -p "$d/rodir"
printf 'x\n' > "$d/a.txt"
chmod -w "$d/rodir"
run "$d/rodir/out.txt" "$d/a.txt"
rc_ro="$RC"; stdout_ro="$STDOUT"; stderr_ro="$STDERR"
chmod +w "$d/rodir"
[ "$rc_ro" -eq 1 ] && [ -z "$stdout_ro" ] && printf '%s' "$stderr_ro" | $GREP -qF "BLOCKER: could not open for writing — $d/rodir/out.txt.partial" && [ ! -e "$d/rodir/out.txt" ] \
    && pass "removal succeeds but the .partial cannot be created — BLOCKER naming the .partial path, no printed line, no file at the output path" \
    || fail "removal succeeds but the .partial cannot be created — BLOCKER naming the .partial path, no printed line, no file at the output path" "rc=$rc_ro stdout=$stdout_ro stderr=$stderr_ro"

# M1: the append guard, distinct from the truncate guard above — SIGXFSZ ignored so a body
# too large fails gracefully (EFBIG) after truncate succeeds, rather than killing the process.
d=$(newdir append_write_failure)
head -c 8000 /dev/zero | tr '\0' 'a' > "$d/big.txt"
( trap '' XFSZ; ulimit -f 1; bash "$SCRIPT" "$d/out.txt" "$d/big.txt" < /dev/null > "$TMPDIR_ROOT/.appstdout" 2>"$ERRFILE" )
app_rc=$?
app_stdout=$(cat "$TMPDIR_ROOT/.appstdout")
app_stderr=$(cat "$ERRFILE")
[ "$app_rc" -eq 1 ] && [ -z "$app_stdout" ] && printf '%s' "$app_stderr" | $GREP -qF "BLOCKER: write failed — $d/out.txt.partial ($d/big.txt)" \
    && pass "a body exceeding a write-size limit after the truncate succeeded — BLOCKER naming the file being written, no printed line" \
    || fail "a body exceeding a write-size limit after the truncate succeeded — BLOCKER naming the file being written, no printed line" "rc=$app_rc stdout=$app_stdout stderr=$app_stderr"

# Low: grep's own read failure during the marker scan must BLOCKER, not be silently read
# as "no marker" and let an unscanned input through to the write stage.
d=$(newdir marker_scan_read_failure)
run "$d/out.txt" /proc/self/mem
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -qF 'BLOCKER: could not scan for header marker — /proc/self/mem' \
    && pass "an input the marker scan cannot read — BLOCKER naming the path, not treated as clean" \
    || fail "an input the marker scan cannot read — BLOCKER naming the path, not treated as clean" "rc=$RC stdout=$STDOUT stderr=$STDERR"

echo "== contract (success path) =="

# 1: two files — both headers in order, both bodies byte-identical, nothing left at .partial.
d=$(newdir two_files)
printf 'alpha body\n' > "$d/a.txt"
printf 'beta body\n' > "$d/b.txt"
run "$d/out.txt" "$d/a.txt" "$d/b.txt"
ha=$($GREP -n -F "${MARKER}$d/a.txt =====" "$d/out.txt" | cut -d: -f1)
hb=$($GREP -n -F "${MARKER}$d/b.txt =====" "$d/out.txt" | cut -d: -f1)
if [ "$RC" -eq 0 ] && [ -n "$ha" ] && [ -n "$hb" ] && [ "$ha" -lt "$hb" ] \
   && $GREP -qF 'alpha body' "$d/out.txt" && $GREP -qF 'beta body' "$d/out.txt" \
   && [ ! -e "$d/out.txt.partial" ]; then
    pass "two files: both headers in order, both bodies present, nothing left at .partial"
else
    fail "two files: both headers in order, both bodies present, nothing left at .partial" "rc=$RC ha=$ha hb=$hb"
fi

# 2: an input whose last byte is not a newline, followed by a second input. Matched with -F
# plus whole-line equality, not a BRE anchor — immune to a TMPDIR carrying a regex metacharacter.
d=$(newdir no_trailing_nl_then_second)
printf 'no newline here' > "$d/a.txt"
printf 'second body\n' > "$d/b.txt"
run "$d/out.txt" "$d/a.txt" "$d/b.txt"
expected_h2="${MARKER}$d/b.txt ====="
matched_h2=$($GREP -F "$expected_h2" "$d/out.txt" | head -1)
if [ "$RC" -eq 0 ] && [ "$matched_h2" = "$expected_h2" ] && $GREP -qF 'second body' "$d/out.txt"; then
    pass "an input whose last byte is not a newline, followed by a second input — both headers at column 0, second body intact"
else
    fail "an input whose last byte is not a newline, followed by a second input — both headers at column 0, second body intact" "rc=$RC matched_h2=$matched_h2"
fi

# 3: an input carrying the header marker indented — packed unchanged.
d=$(newdir marker_indented)
header_line="${MARKER}other-source ====="
printf 'top\n  %s\nbottom\n' "$header_line" > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
if [ "$RC" -eq 0 ] && $GREP -qF "  $header_line" "$d/out.txt"; then
    pass "an input carrying the header marker indented — packed unchanged, run succeeds"
else
    fail "an input carrying the header marker indented — packed unchanged, run succeeds" "rc=$RC stdout=$STDOUT"
fi

# 4: printed lines == awk NR, printed bytes == wc -c.
d=$(newdir lines_bytes_match)
printf 'l1\nl2\nl3\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
printed_lines=$(printf '%s' "$STDOUT" | $GREP -oE 'lines: [0-9]+' | cut -d' ' -f2)
printed_bytes=$(printf '%s' "$STDOUT" | $GREP -oE 'bytes: [0-9]+' | cut -d' ' -f2)
disk_lines=$(awk 'END{print NR}' "$d/out.txt")
disk_bytes=$(wc -c < "$d/out.txt")
if [ "$RC" -eq 0 ] && [ "$printed_lines" = "$disk_lines" ] && [ "$printed_bytes" = "$disk_bytes" ]; then
    pass "printed lines equals awk NR on disk, printed bytes equals wc -c on disk"
else
    fail "printed lines equals awk NR on disk, printed bytes equals wc -c on disk" \
         "printed_lines=$printed_lines disk_lines=$disk_lines printed_bytes=$printed_bytes disk_bytes=$disk_bytes"
fi

# 5: last input's final byte is not a newline — printed lines exceeds wc -l by one.
d=$(newdir last_no_trailing_nl)
printf 'only line, no trailing newline' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
printed_lines=$(printf '%s' "$STDOUT" | $GREP -oE 'lines: [0-9]+' | cut -d' ' -f2)
wc_l=$(wc -l < "$d/out.txt")
if [ "$RC" -eq 0 ] && [ "$printed_lines" -eq $((wc_l + 1)) ]; then
    pass "last input's final byte is not a newline — printed lines exceeds wc -l by one"
else
    fail "last input's final byte is not a newline — printed lines exceeds wc -l by one" "printed_lines=$printed_lines wc_l=$wc_l"
fi

# 6: awk '{print $NF}' on the printed line yields exactly the byte count.
d=$(newdir nf_matches_bytes)
printf 'body\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
nf=$(printf '%s\n' "$STDOUT" | awk '{print $NF}')
printed_bytes=$(printf '%s' "$STDOUT" | $GREP -oE 'bytes: [0-9]+' | cut -d' ' -f2)
if [ "$RC" -eq 0 ] && [ "$nf" = "$printed_bytes" ]; then
    pass "awk '{print \$NF}' on the printed line yields exactly the byte count"
else
    fail "awk '{print \$NF}' on the printed line yields exactly the byte count" "nf=$nf printed_bytes=$printed_bytes"
fi

# 7: a zero-byte input is packed, its header present, the run succeeds.
d=$(newdir zero_byte_input)
: > "$d/empty.txt"
run "$d/out.txt" "$d/empty.txt"
if [ "$RC" -eq 0 ] && $GREP -qF "${MARKER}$d/empty.txt =====" "$d/out.txt"; then
    pass "a zero-byte input is packed, its header present, the run succeeds"
else
    fail "a zero-byte input is packed, its header present, the run succeeds" "rc=$RC"
fi

# 8: a path containing a space is packed correctly.
d=$(newdir with_space)
mkdir -p "$d/dir with space"
printf 'spaced body\n' > "$d/dir with space/a file.txt"
run "$d/out.txt" "$d/dir with space/a file.txt"
if [ "$RC" -eq 0 ] && $GREP -qF "${MARKER}$d/dir with space/a file.txt =====" "$d/out.txt" && $GREP -qF 'spaced body' "$d/out.txt"; then
    pass "a path containing a space is packed correctly"
else
    fail "a path containing a space is packed correctly" "rc=$RC stdout=$STDOUT"
fi

# 9: a relative output path prints as absolute.
d=$(newdir relative_outpath)
printf 'x\n' > "$d/a.txt"
( cd "$d" && bash "$SCRIPT" rel-out.txt a.txt > "$TMPDIR_ROOT/.relout" 2>"$ERRFILE" )
rel_rc=$?
rel_stdout=$(cat "$TMPDIR_ROOT/.relout")
if [ "$rel_rc" -eq 0 ] && printf '%s' "$rel_stdout" | $GREP -qF "bundle: $d/rel-out.txt "; then
    pass "a relative output path prints as absolute"
else
    fail "a relative output path prints as absolute" "rc=$rel_rc stdout=$rel_stdout"
fi

# 10: two runs over one output path — the second overwrites, and both printed figures
# match the second bundle, so a stale count cannot survive a re-pack.
d=$(newdir two_runs)
printf 'first\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
first_bytes=$(printf '%s' "$STDOUT" | $GREP -oE 'bytes: [0-9]+' | cut -d' ' -f2)
printf 'second, a longer body than the first\nwith a second line\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
second_bytes=$(printf '%s' "$STDOUT" | $GREP -oE 'bytes: [0-9]+' | cut -d' ' -f2)
second_lines=$(printf '%s' "$STDOUT" | $GREP -oE 'lines: [0-9]+' | cut -d' ' -f2)
disk_bytes=$(wc -c < "$d/out.txt")
disk_lines=$(awk 'END{print NR}' < "$d/out.txt")
if [ "$RC" -eq 0 ] && [ "$second_bytes" != "$first_bytes" ] && [ "$second_bytes" = "$disk_bytes" ] \
   && [ "$second_lines" = "$disk_lines" ] && $GREP -qF 'second, a longer body' "$d/out.txt"; then
    pass "two runs over one output path: the second overwrites, printed figures (lines and bytes) match the second bundle"
else
    fail "two runs over one output path: the second overwrites, printed figures (lines and bytes) match the second bundle" \
         "first_bytes=$first_bytes second_bytes=$second_bytes disk_bytes=$disk_bytes second_lines=$second_lines disk_lines=$disk_lines"
fi

# 11: exactly one line on stdout on success; every BLOCKER leaves stdout empty, stderr carries BLOCKER:.
d=$(newdir stdout_shape_success)
printf 'x\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
n_stdout_lines=$(printf '%s\n' "$STDOUT" | $GREP -c .)
ok=1
[ "$RC" -eq 0 ] && [ "$n_stdout_lines" -eq 1 ] || ok=0

d=$(newdir stdout_shape_blocker)
run "$d/out.txt"
[ "$RC" -eq 1 ] && [ -z "$STDOUT" ] && printf '%s' "$STDERR" | $GREP -q '^BLOCKER: ' || ok=0

if [ "$ok" -eq 1 ]; then
    pass "exactly one line on stdout on success; every BLOCKER leaves stdout empty with BLOCKER: on stderr"
else
    fail "exactly one line on stdout on success; every BLOCKER leaves stdout empty with BLOCKER: on stderr" "n_stdout_lines=$n_stdout_lines rc=$RC"
fi

# 12: three or more files — every header present, in order (the success path's only
# fixed-size gap; two files is asserted above, N is not).
d=$(newdir three_files)
printf 'one\n' > "$d/a.txt"
printf 'two\n' > "$d/b.txt"
printf 'three\n' > "$d/c.txt"
run "$d/out.txt" "$d/a.txt" "$d/b.txt" "$d/c.txt"
ha=$($GREP -n -F "${MARKER}$d/a.txt =====" "$d/out.txt" | cut -d: -f1)
hb=$($GREP -n -F "${MARKER}$d/b.txt =====" "$d/out.txt" | cut -d: -f1)
hc=$($GREP -n -F "${MARKER}$d/c.txt =====" "$d/out.txt" | cut -d: -f1)
if [ "$RC" -eq 0 ] && [ -n "$ha" ] && [ -n "$hb" ] && [ -n "$hc" ] && [ "$ha" -lt "$hb" ] && [ "$hb" -lt "$hc" ] \
   && $GREP -qF 'one' "$d/out.txt" && $GREP -qF 'two' "$d/out.txt" && $GREP -qF 'three' "$d/out.txt"; then
    pass "three or more files — every header present, in order"
else
    fail "three or more files — every header present, in order" "rc=$RC ha=$ha hb=$hb hc=$hc"
fi

# 13: an input path beginning with a dash, passed relative — every -- guard in the script
# must still resolve it as an operand, not an option.
d=$(newdir leading_dash_input)
printf 'dash body\n' > "$d/-dashfile.txt"
( cd "$d" && bash "$SCRIPT" out.txt -dashfile.txt < /dev/null > "$TMPDIR_ROOT/.dashstdout" 2>"$ERRFILE" )
dash_rc=$?
dash_stdout=$(cat "$TMPDIR_ROOT/.dashstdout")
if [ "$dash_rc" -eq 0 ] && $GREP -qF "${MARKER}-dashfile.txt =====" "$d/out.txt" && $GREP -qF 'dash body' "$d/out.txt"; then
    pass "a leading-dash input path, passed relative — packed correctly, not read as an option"
else
    fail "a leading-dash input path, passed relative — packed correctly, not read as an option" "rc=$dash_rc stdout=$dash_stdout"
fi

# H2: an out-path that is a symlink to an unrelated file — the printed path must name the
# bundle's own location (the symlink's own pathname), not the symlink's pre-removal target.
d=$(newdir outpath_is_symlink)
printf 'unrelated target content\n' > "$d/target.txt"
ln -s "$d/target.txt" "$d/outlink"
printf 'body\n' > "$d/a.txt"
run "$d/outlink" "$d/a.txt"
printed_path=$(printf '%s' "$STDOUT" | $GREP -oE 'bundle: [^ ]+' | cut -d' ' -f2)
if [ "$RC" -eq 0 ] && [ "$printed_path" = "$d/outlink" ] && [ ! -L "$d/outlink" ] \
   && $GREP -qF 'body' "$d/outlink" && [ "$(cat "$d/target.txt")" = "unrelated target content" ]; then
    pass "an out-path that is a symlink to an unrelated file — printed path names the bundle's own location, target untouched"
else
    fail "an out-path that is a symlink to an unrelated file — printed path names the bundle's own location, target untouched" \
         "rc=$RC printed_path=$printed_path stdout=$STDOUT"
fi

# M4: an out-path whose basename looks like an awk name=value assignment must not be read
# as one during the lines read-back (the sibling wc -c redirect is already immune).
d=$(newdir awk_assignment_outpath)
printf 'l1\nl2\nl3\nl4\n' > "$d/a.txt"
run "$d/bundle=v2.txt" "$d/a.txt"
disk_lines=$(awk 'END{print NR}' < "$d/bundle=v2.txt")
printed_lines=$(printf '%s' "$STDOUT" | $GREP -oE 'lines: [0-9]+' | cut -d' ' -f2)
if [ "$RC" -eq 0 ] && [ "$printed_lines" = "$disk_lines" ] && [ "$printed_lines" -eq 5 ]; then
    pass "an out-path shaped like an awk name=value assignment — lines is read from the bundle, not stdin"
else
    fail "an out-path shaped like an awk name=value assignment — lines is read from the bundle, not stdin" "rc=$RC printed_lines=$printed_lines disk_lines=$disk_lines"
fi

# M5: bytes needs an oracle independent of the script's own wc -c idiom — a multibyte UTF-8
# body would still pass a character-count mutant (wc -m) if every fixture stayed ASCII.
d=$(newdir utf8_bytes)
printf 'café — emdash — §section\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
disk_bytes_stat=$(stat -c %s "$d/out.txt")
printed_bytes=$(printf '%s' "$STDOUT" | $GREP -oE 'bytes: [0-9]+' | cut -d' ' -f2)
if [ "$RC" -eq 0 ] && [ "$printed_bytes" = "$disk_bytes_stat" ]; then
    pass "a multibyte UTF-8 body — printed bytes equals stat -c %s, independent of the script's own wc -c idiom"
else
    fail "a multibyte UTF-8 body — printed bytes equals stat -c %s, independent of the script's own wc -c idiom" "rc=$RC printed_bytes=$printed_bytes disk_bytes_stat=$disk_bytes_stat"
fi

# M6: packed bodies must be byte-identical to their originals (cmp, not substring presence),
# and the first header must start at line 1 / column 0, the same as every header after it.
d=$(newdir body_byte_identical)
printf 'alpha\nbody\ntext\n' > "$d/a.txt"
printf 'beta\nbody\ntext\n' > "$d/b.txt"
run "$d/out.txt" "$d/a.txt" "$d/b.txt"
h1_line=$($GREP -n -F "${MARKER}$d/a.txt =====" "$d/out.txt" | cut -d: -f1)
h2_line=$($GREP -n -F "${MARKER}$d/b.txt =====" "$d/out.txt" | cut -d: -f1)
ok=1
[ "$RC" -eq 0 ] || ok=0
[ "$h1_line" = "1" ] || ok=0
if [ "$ok" -eq 1 ] && [ -n "$h2_line" ]; then
    cmp -s <(sed -n "$((h1_line + 1)),$((h2_line - 2))p" "$d/out.txt") "$d/a.txt" || ok=0
    cmp -s <(tail -n "+$((h2_line + 1))" "$d/out.txt") "$d/b.txt" || ok=0
else
    ok=0
fi
if [ "$ok" -eq 1 ]; then
    pass "packed bodies are byte-identical to their originals (cmp), and the first header starts at line 1 / column 0"
else
    fail "packed bodies are byte-identical to their originals (cmp), and the first header starts at line 1 / column 0" "rc=$RC h1_line=$h1_line h2_line=$h2_line"
fi

# V2: a stale .partial left by an earlier interrupted run must be truncated before this
# run writes, not leaked into the bundle — reachable with no filesystem failure at all.
d=$(newdir stale_partial_truncated)
printf 'stale fragment, no header\n' > "$d/out.txt.partial"
printf 'fresh body\n' > "$d/a.txt"
run "$d/out.txt" "$d/a.txt"
if [ "$RC" -eq 0 ] && ! $GREP -qF 'stale fragment' "$d/out.txt" && $GREP -qF 'fresh body' "$d/out.txt"; then
    pass "a stale .partial from an earlier interrupted run is truncated before this run writes, not leaked into the bundle"
else
    fail "a stale .partial from an earlier interrupted run is truncated before this run writes, not leaked into the bundle" "rc=$RC stdout=$STDOUT"
fi

echo
EXPECTED_TESTS=39
total=$((PASS + FAIL))
[ "$total" -eq "$EXPECTED_TESTS" ] \
    && pass "all $EXPECTED_TESTS assertions ran" \
    || fail "all $EXPECTED_TESTS assertions ran" "ran $total — a block skipped itself or EXPECTED_TESTS is stale"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
