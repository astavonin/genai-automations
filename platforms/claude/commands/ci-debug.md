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

# Find associated MR or pipeline (via ci-platform-manager)
ci-platform-manager load-pipeline --branch <branch-name>
```

### Phase 2: Log Collection
```bash
# Get failed jobs
ci-platform-manager pipeline-jobs --failed

# Fetch logs for each failed job
ci-platform-manager job-logs <job-id>
```

### Phase 3: Analysis

Launch **debugger (opus) agent** with:
- Job names and failure context
- Complete job logs
- Task: Analyze failures, identify root causes, suggest fixes following the 6-phase debugger process

### Phase 4: Codex Cross-Model Verification

After the debugger agent produces its diagnosis, run Codex independently:

```bash
printf "Analyze this CI failure. Identify root cause and propose a fix:\n\n<job name and error summary>\n\n<relevant log excerpt>" | codex exec -
```

Compare results per the cross-aggregate rules:
- Both agree → confirmed root cause
- Claude-only → present with confidence level
- Codex-only → present as **"Codex alternative hypothesis"**
- Disagree → present both with supporting evidence

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

3. **Preventive Measures:**
   - How can we prevent similar failures in the future?
   - Should we add tests, update CI config, or improve code?

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

### 1. Extend ci-platform-manager

Add new command: `pipeline-debug`

**Required API calls (GitLab):**
- `GET /projects/:id/merge_requests?source_branch=<branch>`
- `GET /projects/:id/pipelines/:pipeline_id/jobs`
- `GET /projects/:id/jobs/:job_id/trace`

**New handler:** `ci_platform_manager/handlers/pipeline_handler.py`

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
- Create MR: ci-platform-manager create-mr
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
- Integration with `/verify` workflow

## Dependencies

- `ci-platform-manager` with pipeline support
- GitLab or GitHub API access
- `git` command available
- Agent framework (Task tool)

## Notes

- Logs can be large (100KB+); agent should handle gracefully
- Failed jobs may have similar root causes; agent should deduplicate
- Some failures may require manual intervention (infra issues)
- Agent should distinguish between fixable and non-fixable failures
