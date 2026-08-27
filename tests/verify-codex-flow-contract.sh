#!/usr/bin/env bash
# verify-codex-flow-contract.sh — bind the codex-flow failure docs to the messages it can emit.
#
# `tools/codex-flow/README.md` and the consensus protocol's Step E both carry tables that tell an
# operator what to do about a failure, keyed on text from the exit message. Nothing connected
# those keys to `runner.py`, and the same defect shipped twice in two review rounds: first a key
# (`not found`) that also matched an unrelated validation message, then a row (`failed to start`)
# filed under a message prefix that can never carry it. Both were found by a reviewer reading the
# source, which is not a repeatable control.
#
# Scope is deliberately the mechanical half. A key drawn from provider text (`at capacity`,
# `model is not supported`) cannot be checked here — that string lives in OpenAI's service, not in
# this repo — so those rows are exempt and listed as such. What is checkable: every message
# codex-flow itself raises must appear in the docs, and the two tables must agree with each other.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/tools/codex-flow/codex_flow/runner.py"
README="$ROOT/tools/codex-flow/README.md"
PROTOCOL="$ROOT/platforms/claude/skills/domains/quality-attributes/references/consensus-review-protocol.md"

pass=0
fail=0

check() {
    local name="$1" condition="$2"
    if [ "$condition" = "0" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
    fi
}

for path in "$RUNNER" "$README" "$PROTOCOL"; do
    [ -f "$path" ] || { printf 'FAIL: missing file %s\n' "$path"; exit 1; }
done

# 1. Every `codex exec <problem>` message raised by the runner is documented.
#    These are the stage-2 messages: raised by codex-flow itself, so they are literals we own.
while IFS= read -r message; do
    grep -qF "$message" "$README"
    check "README documents runner message: $message" "$?"
done < <(grep -oE '"codex exec [^"{]+\."' "$RUNNER" | tr -d '"' | sort -u)

# 2. The synthesized no-message fallback is documented in both tables. It is the one stage-3 key
#    that is our own literal rather than provider text, so it is the only one bindable here.
FALLBACK="event carried no message"
grep -qF "$FALLBACK" "$RUNNER"; check "runner emits the '$FALLBACK' fallback" "$?"
grep -qF "$FALLBACK" "$README"; check "README documents '$FALLBACK'" "$?"
grep -qF "$FALLBACK" "$PROTOCOL"; check "protocol documents '$FALLBACK'" "$?"

# 3. The two documents enumerate the same stage-3 causes. They drifted once already — the README
#    carried a retired-model row the protocol omitted.
for key in "at capacity" "overloaded" "model is not supported"; do
    grep -qF "$key" "$README"; check "README lists stage-3 key: $key" "$?"
    grep -qF "$key" "$PROTOCOL"; check "protocol lists stage-3 key: $key" "$?"
done

# 4. No table may key on a substring that also matches a different failure. `not found` matched
#    both a retired model and `Request file not found:` — an operator following it would edit the
#    model constant because of a typo in a path.
for ambiguous in '`not found`' '`server_overloaded`'; do
    ! grep -qF "$ambiguous" "$README"
    check "README avoids ambiguous key: $ambiguous" "$?"
    ! grep -qF "$ambiguous" "$PROTOCOL"
    check "protocol avoids ambiguous key: $ambiguous" "$?"
done

# 5. The rollout transcript path keeps its three date components. A single `<date>` placeholder
#    expands to a directory that does not exist, so the documented escape hatch finds nothing.
grep -qF 'sessions/<YYYY>/<MM>/<DD>/' "$PROTOCOL"
check "protocol spells the rollout path with three date components" "$?"
grep -qE 'sessions/(<YYYY>/<MM>/<DD>|[0-9]{4}/[0-9]{2}/[0-9]{2})/' "$README"
check "README spells the rollout path with three date components" "$?"

# 6. The live config and its repo backup agree. The protocol table is read at review time from
#    `~/.claude/`, so a backup-only edit changes nothing about how reviews actually behave.
LIVE="$HOME/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md"
if [ -f "$LIVE" ]; then
    diff -q "$LIVE" "$PROTOCOL" >/dev/null
    check "live protocol matches repo backup" "$?"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
