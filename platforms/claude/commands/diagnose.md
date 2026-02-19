---
name: diagnose
description: Investigate a failure or unexpected behavior using the debugger agent + Codex cross-model verification. Produces a root cause diagnosis and fix recommendation.
---

# Diagnose Command

Investigate a failure using the **debugger (opus)** agent and **Codex** as an independent cross-model verifier.

## Agent

**debugger** (opus model)

## Input

The user provides a failure description, e.g.:
```
/diagnose ci job failing with "VERSION_NUMBER: unbound variable"
/diagnose build.sh crashes when DOCKER_IMAGE_VERSION is local:latest on CI
/diagnose unit test flaky — passes locally, fails in pipeline
```

Optionally attach: log output, stack trace, error message, or relevant file paths.

## Workflow

### Step 1: Claude Debugger Investigation

Invoke the **debugger** agent with:
- Full failure description and any provided logs/traces
- Relevant project context (current working directory, recent changes)
- Instruction to follow the 6-phase process and produce the standard output format

### Step 2: Codex Cross-Model Verification

After the Claude debugger produces its diagnosis, run Codex independently:

```bash
{ printf "DO NOT make any changes. Only print your findings.\n\nDebug this failure. Identify root cause and propose a fix:\n\n<failure description and context>\n\n"; cat <relevant-file-if-applicable>; } | codex exec -
```

Or for log-based failures:
```bash
printf "DO NOT make any changes. Only print your findings.\n\nRoot cause analysis:\n\n<error log>\n\nRelevant code:\n\n$(cat <file>)" | codex exec -
```

Run from the project's working directory.

### Step 3: Cross-Aggregate Results

Compare Claude debugger diagnosis with Codex proposal:

| Result | Action |
|--------|--------|
| Both agree on root cause | High confidence — present as confirmed |
| Both agree on fix approach | Mark fix as **✓ Corroborated by Codex** |
| Claude-only diagnosis | Present with confidence level noted |
| Codex-only finding | Present separately as **"Codex alternative hypothesis"** — different model, worth considering |
| Disagree on root cause | Present both hypotheses with supporting evidence — let user decide |

### Step 4: Present Diagnosis

Output to the user:
- **Root cause** (with confidence: confirmed / likely / hypothesis)
- **Fix recommendation** (with corroboration status)
- **Codex alternative** (if different)
- **Next step**: hand off to `/implement` (coder agent) or `/verify` as appropriate

## Notes

- The diagnose command investigates — it does NOT implement fixes
- After diagnosis, use `/implement` to apply the fix
- For CI/CD-specific failures, prefer `/ci-debug` which has pipeline-specific tooling
- Re-running `/diagnose` on the same issue after a failed fix attempt is expected and encouraged
