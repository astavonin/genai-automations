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
FIX_LOOP_ROUND="$ROOT/platforms/claude/skills/workflows/fix-loop-round/SKILL.md"
ROUND_VERDICT="$ROOT/platforms/claude/skills/workflows/round-verdict/SKILL.md"
CODEX_IMPLEMENT="$ROOT/platforms/claude/commands/codex-implement.md"
CODEX_REVIEW="$ROOT/platforms/claude/commands/codex-review.md"

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

for path in "$RUNNER" "$README" "$PROTOCOL" "$FIX_LOOP_ROUND" "$ROUND_VERDICT"; do
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

# 6. All three fragments' live `~/.claude/` copies match their repo backups — agents read the
#    live tree, and the guard is on the tree so a missing fragment fails rather than skipping.
if [ -d "$HOME/.claude" ]; then
    diff -q "$HOME/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md" "$PROTOCOL" >/dev/null 2>&1
    check "live protocol matches repo backup" "$?"

    diff -q "$HOME/.claude/skills/workflows/fix-loop-round/SKILL.md" "$FIX_LOOP_ROUND" >/dev/null 2>&1
    check "live fix-loop-round/SKILL.md matches repo backup" "$?"

    diff -q "$HOME/.claude/skills/workflows/round-verdict/SKILL.md" "$ROUND_VERDICT" >/dev/null 2>&1
    check "live round-verdict/SKILL.md matches repo backup" "$?"

    diff -q "$HOME/.claude/commands/codex-implement.md" "$CODEX_IMPLEMENT" >/dev/null 2>&1
    check "live codex-implement.md matches repo backup" "$?"

    diff -q "$HOME/.claude/commands/codex-review.md" "$CODEX_REVIEW" >/dev/null 2>&1
    check "live codex-review.md matches repo backup" "$?"
fi

# 7. Every progress monitor resolves its log directory through `codex-flow progress-dir` rather
#    than rebuilding the path in shell. Three copies of a hand-written `/tmp/...` path once
#    pointed where the tool never wrote, so monitoring was silently dead on every run; the
#    replacement glob then scoped across every repository's directory, which is worse — it
#    attaches to a foreign run and prints its `workflow_complete` as this run's success. Both
#    defects are shaped as a path expression in Markdown that nothing compared to the tool.
for monitor in "$CODEX_IMPLEMENT" "$CODEX_REVIEW" "$PROTOCOL"; do
    name="$(basename "$monitor")"

    grep -q 'PROGRESS_DIR=$(codex-flow progress-dir' "$monitor"
    check "$name resolves the progress dir through the CLI" "$?"

    grep -qE 'ls -t "\$PROGRESS_DIR"/\*\.jsonl' "$monitor"
    check "$name globs only its own repository's directory" "$?"

    grep -q 'stat -c %Y "$PROGRESS"' "$monitor"
    check "$name rejects a log left by an earlier run" "$?"

    grep -q 'tail -n +1 -f "$PROGRESS"' "$monitor"
    check "$name streams the log from its first line" "$?"

    ! grep -qE 'codex-flow-progress-state|XDG_STATE_HOME:-|runs/\*/' "$monitor"
    check "$name derives no state path of its own" "$?"
done

# 8. `progress-dir` reports the directory a run writes into. Asserted against the CLI rather than
#    against `repository_state_dir()` directly: the monitors call the CLI, so that is the surface
#    whose drift breaks them.
if command -v codex-flow >/dev/null 2>&1; then
    probe_state="$(mktemp -d)"
    probe_repo="$(mktemp -d)"
    probe_request="$probe_state/design.md"
    {
        printf '# Design — progress-dir probe\n\n## 3. Implementation Context\n\n'
        printf '**Repository:** `%s`\n\n' "$probe_repo"
        printf '**Functional Requirements:**\n- probe\n\n'
        printf '**Non-Functional Requirements:**\n- probe\n\n'
        printf '**Constraints:**\n- none\n\n'
        printf '**Verification:**\n```bash\ntrue\n```\n\n'
        printf '**Context Files:**\n- `README.md`\n'
    } > "$probe_request"

    expected="$(
        XDG_STATE_HOME="$probe_state" python3 -c '
import sys
from pathlib import Path
from codex_flow.progress import repository_state_dir
print(repository_state_dir(Path(sys.argv[1])))
' "$probe_repo" 2>/dev/null
    )"
    actual="$(XDG_STATE_HOME="$probe_state" codex-flow progress-dir "$probe_request" 2>/dev/null)"

    [ -n "$expected" ] && [ "$actual" = "$expected" ]
    check "progress-dir agrees with repository_state_dir()" "$?"

    XDG_STATE_HOME="$probe_state" codex-flow progress-dir "$probe_request" 2>/dev/null | grep -q "^$probe_state/codex-flow/runs/"
    check "progress-dir honours XDG_STATE_HOME" "$?"

    printf '# Meeting Notes\n\nnothing\n' > "$probe_state/notes.md"
    ! XDG_STATE_HOME="$probe_state" codex-flow progress-dir "$probe_state/notes.md" >/dev/null 2>&1
    check "progress-dir fails rather than guessing on an unrecognized request" "$?"

    rm -rf "$probe_state" "$probe_repo"
else
    printf '  SKIP: codex-flow not on PATH — progress-dir checks not run\n'
fi

# 9. Every name in the feature-disable list is still registered in the binary. A de-registered
#    name aborts `codex exec` with exit 1, taking both workflows down at launch.
if command -v codex >/dev/null 2>&1; then
    features="$(codex features list 2>/dev/null)"
    for feature in $(sed -n '/^DISABLED_EXTERNAL_TOOL_FEATURES = (/,/^)/p' "$RUNNER" | grep -oE '"[a-z_]+"' | tr -d '"'); do
        printf '%s\n' "$features" | awk -v f="$feature" '$1 == f && $2 != "removed" { found = 1 } END { exit !found }'
        check "codex features list still registers '$feature'" "$?"
    done
else
    printf '  SKIP: codex not on PATH — feature-registration checks not run\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
