---
name: ci-debug
description: Debug failed CI pipeline jobs and analyze logs
---

# CI Debug Command

Automatically detect failed CI/CD pipeline jobs in the current branch, fetch logs, and initiate investigation.

## Overview

This command:
1. Detects current branch
2. Finds associated merge request or pipeline
3. Identifies failed jobs
4. Fetches job logs
5. Launches investigation agent to analyze failures and suggest fixes

## Workflow

### Phase 1: Detection
```bash
# Get current branch
git branch --show-current

# Find associated MR or pipeline (via projctl)
projctl load-pipeline --branch <branch-name>
```

### Phase 2: Log Collection
```bash
# Get failed jobs
projctl pipeline-jobs --failed

# Fetch logs for each failed job
projctl job-logs <job-id>
```

### Phase 3: Analysis

A red CI job is an observed failure by definition. Read the regression rule before launching the agent:

```
Read ~/.claude/skills/workflows/regression-test/SKILL.md
```

Launch **debugger (opus) agent** with:
- Job names and failure context
- Complete job logs
- Task: Analyze failures, identify root causes, suggest fixes following the 7-phase debugger process, and produce a **Regression Test Specification per failure** (Phase 7)

### Phase 4: Codex Cross-Model Verification

After the debugger agent produces its diagnosis, run Codex independently:

```bash
~/.claude/scripts/codex-pipe \
  --prompt "Analyze this CI failure. Identify root cause, propose a fix, and specify the regression test (unit or integration, with test file, precondition, and assertion) that would make this pipeline fail on regression:\n\n<job name and error summary>\n\n<relevant log excerpt>" \
  --output /tmp/codex-ci-debug.txt
```

Compare results per the cross-aggregate rules:
- Both agree → confirmed root cause
- Claude-only → present with confidence level
- Codex-only → present as **"Codex alternative hypothesis"**
- Disagree → present both with supporting evidence
- Differ on regression test level → prefer the integration specification

### Phase 5: Regression Coverage

CI failures are disproportionately composition failures — env vars, image tags, job ordering, build flags, cache keys. These are almost never reproducible from isolated logic, so **default to integration coverage**, and when the pipeline's own structure was at fault, add a CI-level assertion (config validator, lint rule, or smoke job) so the pipeline fails on regression instead of the next developer discovering it.

For each root cause, present one line to the user:

```
<job name> → <root cause> → regression test: <level> <test file>::<test name>
```

**Record each root cause in the ledger (mandatory).** First resolve where it goes:

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

Most CI fixes are unticketed, so the orphan fallback is the common path — use its deterministic branch-derived slug, not a description, or `/review-fix` will later resolve a different folder and find nothing. Echo the resolved path.

Append one entry per root cause to `<issue-folder>/observed-failures.md` using the entry format in the regression-test fragment, with `**Status:** open`, creating the file and its orphan folder if absent. This is what makes the gate fire later; a CI failure diagnosed on Monday and fixed on Wednesday has no other anchor. Then push it to backup:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Two CI-specific rules:
- **A green pipeline is not the regression test.** Re-running the job until it passes proves the fix worked once, not that the failure is guarded.
- **Deduplicated root causes still need per-symptom coverage.** If three jobs shared one root cause, one test covering that root cause is sufficient — but confirm each job's symptom is actually reachable through it rather than assuming.

Failures with no repository component, or where nothing assertable changed, are out of scope per the fragment — record them as `**Status:** out-of-scope` with the reason rather than omitting them.

### Phase 6: Handoff

`/ci-debug` diagnoses; it does not fix. Hand off explicitly, or the gate never runs:
- Pass the per-root-cause Regression Test specifications to `/implement` alongside the fixes, **with the resolved issue-folder path** — re-deriving it downstream is what produces ledger misses
- For unticketed hotfixes that will never reach `/verify`, route the result to `/review-fix` instead — that is where the gate fires for work that skips the numbered workflow phases
- Do not treat a re-run that goes green as completion

## Agent Prompt Template

```
Analyze the failed CI/CD pipeline jobs and provide actionable fixes.

## Context
- Branch: {branch_name}
- Pipeline: {pipeline_id}
- Failed Jobs: {job_count}

## Failed Jobs

{for each failed job:}
### Job: {job_name}
- Status: {status}
- Stage: {stage}
- Duration: {duration}
- Error Summary: {error_extract}

**Full Logs:**
```
{job_logs}
```
{end for}

## Task

1. **Identify Root Causes:**
   - What caused each job to fail?
   - Are failures related or independent?
   - Is this a code issue, config issue, or infrastructure issue?

2. **Suggest Fixes:**
   - Provide specific, actionable fixes for each failure
   - Prioritize fixes by impact
   - Include code snippets or config changes if applicable

3. **Specify Regression Tests (MANDATORY — one per root cause):**
   Each fix ships with a test that reproduces the failure. Use the `## Regression Test` schema
   from your Phase 7 output format, once per root cause, plus one CI-specific field:
   - **CI-level guard** (when the pipeline structure itself was at fault): the validator, lint
     rule, or smoke job that makes the pipeline fail on regression, and what makes it fail

   Default to integration: CI failures are usually env/composition failures that a mocked unit
   test cannot catch. If a failure genuinely cannot be tested, say so explicitly and name the
   waiver category — do not omit the specification.

4. **Preventive Measures (beyond the regression tests above):**
   - Are other jobs or code paths exposed to the same root cause?
   - Should CI config, tooling, or local-CI parity change to catch this class earlier?

Please provide a structured analysis with clear next steps.
```

## Usage

```bash
# In a branch with failed CI
/ci-debug

# Optionally specify MR or pipeline
/ci-debug !123
/ci-debug pipeline-456789
```

## Implementation Steps

> **Historical.** The pseudo-code and API notes below are the original projctl design sketch for this command. They predate Phases 5 and 6 (ledger write and handoff) and are not a current description of the flow. Follow the Workflow section above.

### 1. Extend projctl

Add new command: `pipeline-debug`

**Required API calls (GitLab):**
- `GET /projects/:id/merge_requests?source_branch=<branch>`
- `GET /projects/:id/pipelines/:pipeline_id/jobs`
- `GET /projects/:id/jobs/:job_id/trace`

**New handler:** `projctl/handlers/pipeline_handler.py`

### 2. Command Execution

```python
# Pseudo-code
def cmd_ci_debug(args):
    # 1. Get current branch
    branch = get_current_branch()

    # 2. Find MR or pipeline
    mr = load_mr_by_branch(branch)
    pipeline = get_latest_pipeline(mr)

    # 3. Get failed jobs
    failed_jobs = get_failed_jobs(pipeline)

    if not failed_jobs:
        print("✓ No failed jobs found")
        return

    # 4. Fetch logs for each failed job
    logs = {}
    for job in failed_jobs:
        logs[job.name] = fetch_job_logs(job.id)

    # 5. Prepare context for agent
    context = format_failure_context(failed_jobs, logs)

    # 6. Launch debugger agent
    launch_agent(
        type="debugger",
        task=f"Analyze CI failures and suggest fixes\n\n{context}"
    )
```

## Output Format

**Success:**
```
=== CI Debug ===
Branch: feature/add-spanish-sync
MR: !134 "Add Spanish vocabulary sync"
Pipeline: #456789

Failed Jobs (2):
  ✗ test:unit (stage: test) - Exit code 1
  ✗ lint:pylint (stage: lint) - Exit code 2

Fetching logs...
✓ Logs retrieved (2 jobs)

Launching investigation agent...
```

**No Failures:**
```
=== CI Debug ===
Branch: feature/add-spanish-sync
MR: !134 "Add Spanish vocabulary sync"
Pipeline: #456789

✓ All jobs passed
No investigation needed.
```

**No Pipeline:**
```
=== CI Debug ===
Branch: feature/add-spanish-sync

✗ No merge request or pipeline found for this branch.

Suggestions:
- Push the branch: git push -u origin feature/add-spanish-sync
- Create MR: projctl create-mr
```

## Error Handling

- **No git repository:** Exit with clear message
- **Detached HEAD:** Require branch name as argument
- **No CI configured:** Detect and inform user
- **API errors:** Graceful fallback with manual instructions

## Future Enhancements

- Support for GitHub Actions
- Parallel log fetching
- Log caching (don't re-fetch on retry)
- Interactive job selection
- Automatic retry with suggested fixes applied

## Dependencies

- `projctl` with pipeline support
- GitLab or GitHub API access
- `git` command available
- Agent framework (Task tool)

## Notes

- Logs can be large (100KB+); agent should handle gracefully
- Failed jobs may have similar root causes; agent should deduplicate
- Some failures may require manual intervention (infra issues)
- Agent should distinguish between fixable and non-fixable failures
- **Every fix that changes assertable behaviour ships with a regression test.** A re-run turning the pipeline green does not satisfy the gate. Enforcement is `/verify` Steps 6a–6d for ticketed work and `/review-fix` for hotfixes — both read `observed-failures.md`, so Phase 5's ledger write is what makes either fire.
