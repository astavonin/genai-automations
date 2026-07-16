---
name: devops
description: DevOps implementation and review guidance for CI/CD pipelines (GitHub Actions, GitLab, self-hosted runners), Docker/BuildKit images, cache-heavy embedded or cross-compilation pipelines, HIL/on-device verification, and automation scripts. Use when creating, modifying, debugging, or reviewing CI configs, Dockerfiles, Makefiles, shell automation, package/container publishing, cache management, or hardware-in-the-loop workflows.
allowed-tools: Bash, Glob, Grep, Read, Write, Edit, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 2.0.0
  category: domains
  tags: [devops, docker, ci-cd, infrastructure, hil, self-hosted-runners]
---

# DevOps Skill

Infrastructure automation, containerization, CI/CD pipelines, and developer experience optimization. Apply this skill for infrastructure work where correctness depends on CI behavior, runner constraints, credentials, caches, artifacts, or physical devices. Combine with the relevant language skill — for shell scripts, read `skills/languages/shell/SKILL.md` before editing.

## Core Principles

### Local-CI Parity
Create identical experiences between local development and CI environments:
- Use same Docker images and versions locally and in CI
- Shared scripts (Makefile, shell scripts, task runners) work in both contexts
- Avoid CI-specific magic — if it runs in CI, developers can run it locally
- Environment variables with sensible defaults for local development
- Document unavoidable differences
- **Build commands use identical flags across all invocation sites** — Makefile targets and every CI job that builds the same artifact must agree on `--platform`, cache args, `--provenance`, `--sbom`, and any other flags; differences are bugs unless explicitly documented

### Resource Efficiency
Optimize resource consumption aggressively:
- **Docker Images:** Multi-stage builds, minimal base images (Alpine, distroless, slim), proper layer caching
- **CI Pipelines:** Dependency caching, shallow clones, smart parallelization
- **Memory & CPU:** Appropriate resource limits, avoid unnecessary services
- **Storage:** Clean up artifacts, effective .dockerignore, minimize image sizes
- **Time:** Fast feedback loops, fail fast, skip unnecessary steps

### Developer Experience
Every change should make developers' lives easier:
- Seamless workflows between local and CI
- Easy to understand, debug, and modify
- Clear error messages and validation
- Sensible defaults that work out of the box (`.env.example` with documented defaults, no required secrets for local dev)

## Hard Rules

- Never print, commit, or document real tokens, PATs, SSH keys, passwords, registry auth JSON, or credential-bearing URLs. Example commands must use placeholders.
- Do not add `latest` as the only image reference for CI execution. Pin by explicit project version, commit SHA, or generated version tag; reserve `latest` for default-branch promotion only.
- Do not retry long deterministic timeouts blindly. Retrying a 6–12 hour timeout wastes scarce runner time unless there is evidence of runner infrastructure failure.
- Do not move large caches as artifacts between jobs unless there is no better cache/server path. Large cache artifacts can dominate pipeline time and storage.
- Do not use `ln -sfn` as if it replaces an existing directory. Remove the target first or use a platform-appropriate no-dereference replacement, then verify the result.
- Do not rely on prompt comments or YAML naming for hard invariants. Enforce them with pipeline rules/conditions, job dependencies, concurrency/resource-group directives, script validation, tests, or runtime checks.
- Destructive automation must be safe to rerun or have an explicit dry-run/confirmation path. Non-interactive CI jobs must encode allowed scope with rules and script validation.

## Initial Pass

Before changing CI or automation:

1. Read project guidance: `CLAUDE.md`, `AGENTS.md`, `CODEX.md`, CI docs, and planning/design docs when present.
2. Inspect `.gitlab-ci.yml` / `.github/workflows/`, included CI files, `Dockerfile*`, `Makefile`, `dev.sh`, `ci/`, `scripts/`, project-specific version files such as `VERSION` or CI image version YAML, and runner/device docs.
3. Identify the execution contract: local command, CI job, runner tags, required image version, caches, artifacts, credentials, device access, and expected reports.
4. Preserve local-CI parity. Prefer one shared script or wrapper that both local and CI call over copying logic into YAML.
5. For live GitLab/GitHub state, use `projctl` — check its help first; extend the wrapper (source at `~/projects/projctl`) rather than bypassing it with raw `glab`/`gh` or direct API calls.
6. Respect wrapper constraints from project guidance. Do not broaden a targeted command to full-tree or `--all` modes when the project forbids them or when the cost is disproportionate.
7. Document intentional local/CI differences and required environment variables rather than hiding them in CI-only branches.
8. Treat self-hosted runner capacity, disk space, physical devices, and cache servers as scarce resources that need explicit serialization, timeouts, cleanup, and diagnostics.

## Review Focus

Use this when reviewing another engineer's CI or automation changes. Lead with defects that can waste hours, leak secrets, corrupt cache state, leave devices dirty, publish incomplete artifacts, or make local reproduction impossible.

Check at minimum:

- local command and CI job call the same implementation path
- runner tags and concurrency directives (GitLab `resource_group`, GitHub Actions `concurrency`) match the scarce resource being used
- caches are scoped by architecture, sanitizer/toolchain variant, and invalidation version
- artifact uploads fail on HTTP errors and produce checksums or machine-readable evidence
- teardown steps (GitLab `after_script`, GitHub Actions `if: always()` steps) have the state they need through files or persisted outputs, not shell variables from another job phase
- cleanup runs on failure and leaves enough logs/artifacts for diagnosis
- HIL jobs have preflight checks, bounded timeouts, non-interactive CI mode, device log capture, and teardown
- Docker build flags match across Makefile, local scripts, and CI jobs
- registry, package, and image paths use one canonical variable instead of redundant aliases
- destructive, release, or cleanup automation is idempotent or has a tested dry-run path

## Verification

Prefer project-native validation. When available, run:

- GitLab CI lint, GitHub Actions `act`, or equivalent config validation
- `bash -n`, `sh -n`, `shellcheck`, and shell behavior tests for changed scripts
- Docker build or targeted build stage for changed Dockerfiles, if feasible
- local wrapper command that mirrors CI, such as `./dev.sh`, `make build`, or the project CI runner script
- targeted wrapper checks when the project forbids full-tree modes, such as changed-file lint instead of broad `--all`
- HIL verifier in `--ci` or non-interactive mode when the task is device-verifiable; if a design/spec/project guide provides concrete device commands, run those commands as an implementation completion gate

If full CI or device verification cannot run locally after checking the documented entry point, report the implementation as incomplete/blocked with the exact CI job or device entry point that must provide evidence.

## Reference Routing

Read only the reference that matches the task.

**General (cross-platform):**
- `references/ci-cd.md` — GitHub Actions + GitLab CI examples, caching patterns, matrix builds, concurrency, artifact retention
- `references/docker.md` — Multi-stage builds, layer caching, base image selection, security patterns, BuildKit features
- `references/local-ci-parity.md` — Shared scripts, Docker Compose, `act`/`gitlab-runner`, build-flag parity across sites

**Deep operational references (GitLab-flavored terminology throughout):**
- `references/gitlab-self-hosted-ci.md` — GitLab CI YAML, self-hosted runner tags, Docker image publishing, package registry uploads, secret handling, CI debugging (GitLab-native; see `references/ci-cd.md` for GitHub Actions patterns)
- `references/yocto-cache-heavy-ci.md` — Yocto/Buildroot/SDK, sstate/downloads/ccache, rsync cache-server, long-running embedded build pipelines (GitHub Actions equivalents in the file's Terminology preamble)
- `references/hil-automation.md` — HIL, ADB/SSH devices, on-device verification, device scenario frameworks, JUnit reports, CI hardware runners (GitHub Actions equivalents in the file's Terminology preamble)

## Quality Checks

Self-check before finalizing your own DevOps configuration changes:
- [ ] Can developers run this locally with minimal setup?
- [ ] Does it work the same way in CI?
- [ ] Are resources used efficiently?
- [ ] Proper error handling and helpful messages?
- [ ] Configuration properly documented?
- [ ] Secrets handled securely?
- [ ] Caching implemented where beneficial?
- [ ] Versions pinned for reproducibility?
- [ ] Build flags (`--platform`, `--provenance`, `--sbom`, cache args) identical across all invocation sites (Makefile, each CI job, wrapper scripts)?
- [ ] No redundant variable aliases pointing to the same registry path or resource?
