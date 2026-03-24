---
name: Use |& instead of 2>&1 |
description: Always use |& to combine stdout+stderr in pipelines, never 2>&1 |
type: feedback
---

Use `|&` instead of `2>&1 |` when piping combined stdout+stderr.

**Why:** Claude Code's permission heuristic flags any `>` character in a Bash command as potential file redirection and prompts for confirmation — even for `2>&1`. Using `|&` achieves the same result (pipe both streams) without triggering the prompt.

**How to apply:** Any time you would write `cmd 2>&1 | next`, write `cmd |& next` instead. Applies to all Bash tool calls and shell commands in scripts or documentation examples.
