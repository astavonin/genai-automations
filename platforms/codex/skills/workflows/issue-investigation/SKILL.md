---
name: issue-investigation
description: Structured investigation workflow for defects, incidents, and ambiguous behavior.
---

# Issue Investigation Workflow Skill

Investigate issues with evidence-based analysis and produce clear, actionable findings.

## When To Use
- Bug reports and regressions
- Incidents or flaky behavior
- Performance anomalies

## Required Inputs
- Issue/ticket link or description
- Repro steps or environment details
- Logs, metrics, or traces (if available)
- Recent changes or suspect commits (if known)

## Workflow

1. **Intake & Triage**
   - Clarify expected vs actual behavior
   - Identify scope, severity, and impact

2. **Reproduce or Simulate**
   - Attempt reproduction or reason about reproduction gaps
   - Record environment assumptions

3. **Trace & Evidence**
   - Inspect relevant code paths
   - Collect logs/metrics traces and file references

4. **Hypotheses & Validation**
   - List plausible root causes
   - Validate or falsify with evidence

5. **Next Steps**
   - Recommend fixes, tests, or instrumentation

## Output Template

Use: `references/investigation-template.md`

## Guardrails
- Prefer evidence over speculation
- Label hypotheses vs confirmed findings
- Call out missing data explicitly
