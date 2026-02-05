---
name: code-review
description: End-to-end code review workflow focused on quality attributes and actionable findings.
---

# Code Review Workflow Skill

Deliver consistent, high-signal reviews using the quality-attributes checklist and language standards.

## When To Use
- Reviewing PR/MR diffs or patches
- Assessing design-to-implementation adherence
- Evaluating tests, safety, performance, and maintainability

## Required Inputs
- Repository and target branch/commit
- Diff or patch source
- Test and static analysis results (if available)
- Linked issue/ticket (if any)

## Workflow

1. **Intake & Scope**
   - Confirm review goal (bugfix, feature, refactor)
   - Identify risk areas and change surface

2. **Evidence Collection**
   - Inspect diffs and impacted files
   - Check tests and build results
   - Note missing coverage or missing evidence

3. **Quality Attributes Review**
   - Use `~/.codex/skills/domains/quality-attributes/references/review-checklist.md`
   - Cross-check against language and code-quality standards

4. **Output**
   - Produce findings using the template below
   - Prioritize by severity and provide concrete recommendations

## Output Template

Use: `references/review-output-template.md`

## Guardrails
- Review only; do not implement fixes
- If evidence is missing, ask for it explicitly
- Be specific: cite files, functions, and behaviors
- Call out test gaps and verification gaps
