---
name: feedback-projctl-load-shell-comment
description: projctl load must not use
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 91c852b3-c48e-4362-9c41-17284cd43801
---

Never use `projctl load issue #N` or `projctl load mr !N` in shell commands — the unquoted `#` is treated as a shell comment and stripped, leaving `projctl load issue` with no reference argument (exit code 2).

**Why:** In interactive zsh/bash shells, `#` starts a comment after whitespace; `!N` triggers history expansion. Both are silently dropped before projctl ever sees them.

**How to apply:** Always use bare numbers: `projctl load issue 298`, `projctl load mr 42`. The type argument already disambiguates the resource kind. The config files have been corrected to reflect this.
