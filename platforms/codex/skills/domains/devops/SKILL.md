---
name: devops
description: DevOps implementation and review guidance for GitLab CI/CD, self-hosted runners, Docker/BuildKit images, cache-heavy embedded or cross-compilation pipelines, HIL/on-device verification, and automation scripts. Use when creating, modifying, debugging, or reviewing `.gitlab-ci.yml`, CI includes, runner tags, `resource_group`, Dockerfiles, Makefiles, CI shell scripts, package or container publishing, GitLab package/registry automation, Yocto/sstate caches, ADB/SSH device verification, or hardware-in-the-loop workflows.
---

# DevOps Skill

Use this skill for infrastructure work where correctness depends on CI behavior, runner constraints, credentials, caches, artifacts, or physical devices. Apply it with the relevant language skill; for shell scripts, read `skills/languages/shell/SKILL.md` before editing.

## Source Model

This guidance is distilled from three primary local patterns:

- An embedded Linux/Yocto repository with huge caches, long builds, direct container execution, cache-server rsync, Generic Packages publishing, and failure diagnostics.
- An application repository with GitLab CI backed by Dockerized `./dev.sh`, variant-specific build caches, sanitizer/cross-compile jobs, and HIL verification with mock tests and JUnit reporting.
- A CI support repository with shared CI image builds, local Makefile parity, BuildKit/cache flags, version tags, release automation, and explicit dependency layering.

## Initial Pass

Before changing CI or automation:

1. Read project guidance: `AGENTS.md`, `CLAUDE.md`, `CODEX.md`, CI docs, and planning/design docs when present.
2. Inspect `.gitlab-ci.yml`, included CI files, `Dockerfile*`, `Makefile`, `dev.sh`, `ci/`, `scripts/`, project-specific version files such as `VERSION` or CI image version YAML, and runner/device docs.
3. Identify the execution contract: local command, CI job, runner tags, required image version, caches, artifacts, credentials, device access, and expected reports.
4. Inspect real CI pipeline/job evidence when CI behavior is in scope: job logs, artifacts, runner tags, image versions, cache/artifact inputs, and invoked commands.
5. Preserve local-CI parity. Prefer one shared script or wrapper that both local and CI call over copying logic into YAML.
6. For live GitLab and CI state, prefer the project management wrapper when present. When `projctl` is available, use `projctl pipeline-debug` for failed branch/MR pipelines and `projctl pipeline-debug --job-id <id>` for a specific job trace. Check its help first; in this repo family, extend `projctl` rather than bypassing it with raw GitLab CLI or API calls.
7. Respect wrapper constraints from project guidance. Do not broaden a targeted command to full-tree or `--all` modes when the project forbids them or when the cost is disproportionate.
8. Document intentional local/CI differences and required environment variables rather than hiding them in CI-only branches.
9. Treat self-hosted runner capacity, disk space, physical devices, and cache servers as scarce resources that need explicit serialization, timeouts, cleanup, and diagnostics.

## Reference Routing

Read only the reference that matches the task:

- `references/gitlab-self-hosted-ci.md`: GitLab CI YAML, self-hosted runner tags, Docker image publishing, package registry uploads, secret handling, and CI debugging.
- `references/yocto-cache-heavy-ci.md`: Yocto, Buildroot, SDK, large Docker image, sstate/downloads/ccache, rsync cache-server, and long-running embedded build pipelines.
- `references/hil-automation.md`: HIL, ADB/SSH devices, on-device verification, device scenario frameworks, JUnit reports, and CI hardware runners.

## Hard Rules

- Never print, commit, or document real tokens, PATs, SSH keys, passwords, registry auth JSON, or credential-bearing URLs. Example commands must use placeholders.
- Do not add `latest` as the only image reference for CI execution. Pin by explicit project version, commit SHA, or generated version tag; reserve `latest` for default-branch promotion only.
- Do not retry long deterministic timeouts blindly. Retrying a 6-12 hour timeout wastes scarce runner time unless there is evidence of runner infrastructure failure.
- Do not move large caches as artifacts between jobs unless there is no better cache/server path. Large cache artifacts can dominate pipeline time and storage.
- Do not use `ln -sfn` as if it replaces an existing directory. Remove the target first or use a platform-appropriate no-dereference replacement, then verify the result.
- Do not rely on prompt comments or YAML naming for hard invariants. Enforce them with `rules`, `needs`, `resource_group`, script validation, tests, or runtime checks.
- Destructive automation must be safe to rerun or have an explicit dry-run/confirmation path. Non-interactive CI jobs must encode allowed scope with rules and script validation.

## Review Focus

When reviewing CI or automation, lead with defects that can waste hours, leak secrets, corrupt cache state, leave devices dirty, publish incomplete artifacts, or make local reproduction impossible.

Check at minimum:

- local command and CI job call the same implementation path
- runner tags and `resource_group` match the scarce resource being used
- caches are scoped by architecture, sanitizer/toolchain variant, and invalidation version
- artifact uploads fail on HTTP errors and produce checksums or machine-readable evidence
- `after_script` has the state it needs through files or persisted outputs, not shell variables from another phase
- cleanup runs on failure and leaves enough logs/artifacts for diagnosis
- HIL jobs have preflight checks, bounded timeouts, non-interactive CI mode, device log capture, and teardown
- Docker build flags match across Makefile, local scripts, and CI jobs
- registry, package, and image paths use one canonical variable instead of redundant aliases
- destructive, release, or cleanup automation is idempotent or has a tested dry-run path

## Verification

Prefer project-native validation. When available, run:

- GitLab CI lint or equivalent config validation
- relevant real CI job or pipeline verification, with job URL/id or artifact/log evidence inspected before finalizing
- `bash -n`, `sh -n`, `shellcheck`, and shell behavior tests for changed scripts
- Docker build or targeted build stage for changed Dockerfiles, if feasible
- local wrapper command that mirrors CI, such as `./dev.sh`, `make build`, or the project CI runner script
- targeted wrapper checks when the project forbids full-tree modes, such as changed-file lint instead of broad `--all`
- HIL verifier in `--ci` or non-interactive mode when the task is device-verifiable; if a design/spec/project guide provides concrete device commands, run those commands as an implementation completion gate

If full CI or device verification cannot run locally after checking the documented entry point, report the implementation as incomplete/blocked with the exact CI job or device entry point that must provide evidence.
