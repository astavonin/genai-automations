# GitLab And Self-Hosted CI

Use this reference when editing or reviewing `.gitlab-ci.yml`, CI includes, Docker image build jobs, package uploads, self-hosted runner selection, or failed GitLab pipeline behavior.

## Discovery Checklist

- Read `.gitlab-ci.yml` plus any local or remote `include` files referenced by it.
- Locate runner tag anchors, global `variables`, `workflow`, stage order, `default`, `before_script`, `rules`, `needs`, caches, artifacts, `resource_group`, and publish/release jobs.
- Find the local equivalent: `Makefile`, `dev.sh`, `ci/dev/*.sh`, `docker/build*.sh`, or project docs.
- Check version inputs: `VERSION`, CI image version files, image tag variables, package names, and promotion rules.
- Identify all credentials: GitLab job token, registry credentials, PAT variables, SSH keys, BuildKit secrets, and secret-bearing URL rewrites.
- If the project uses `projctl` for GitLab/GitHub management, use it for issues, MRs, comments, sync, and CI pipeline debugging. Start failed-CI investigation with `projctl pipeline-debug`; use `projctl pipeline-debug --job-id <id>` when a job ID is already known. Check `projctl --help` and subcommand help before raw alternatives. In this repo family, extend `projctl` rather than bypassing it with `glab`, `gh`, or direct API calls.

## GitLab Job Design

- Use runner `tags` deliberately. A job with multiple tags requires a runner with all of them. Untagged jobs can get stuck when available runners only accept tagged jobs.
- Use `resource_group` for scarce resources: hardware devices, flash rigs, Yocto/build runners with limited disk, shared cache mutation, or release/publish slots.
- Use `interruptible` and `workflow:auto_cancel` for expensive branch jobs that become obsolete on new commits. Do not make deployment, release, flashing, or cleanup jobs interruptible unless the rollback path is explicit.
- Use `needs` to shorten feedback loops and control artifact download. Set `artifacts: false` when a dependency is only ordering, not data transfer.
- Keep expensive work out of `before_script` when downstream jobs do not need it. Put reusable setup into scripts that are testable locally.
- Avoid copying large shell programs into YAML. Extract them to `ci/*.sh` or a project wrapper, syntax-check them, and call them from CI.
- Make rerunnable jobs idempotent. Release, publish, and cleanup jobs should define what happens when the tag, package, cache object, or remote path already exists.

## Rules And Triggers

- Be explicit about `push`, `merge_request_event`, `schedule`, `web`, and default-branch behavior.
- Avoid duplicate pipelines for the same commit unless that is intentional.
- Keep default branch publish/promotion jobs narrower than validation jobs.
- For manual pipelines with optional dependencies, use optional `needs` only when the job can genuinely run with pre-existing artifacts or override inputs.

## Cache Strategy

- Separate cache keys by architecture, build mode, sanitizer, toolchain, SDK version, and invalidation generation. Shared caches are useful only when the object formats and flags are compatible.
- Use branch cache reuse intentionally. Feature branches can inherit a default-branch cache, but writes back to a shared cache should be justified.
- Save caches `when: always` only when failed jobs can produce useful cache entries and corruption risk is controlled.
- Do not use CI artifacts for large mutable caches unless the platform cache or external cache server is not viable. Artifacts are better for bounded build outputs, diagnostics, reports, and package payloads.
- Log cache hit/miss, size, and key information before expensive build work starts.

## Artifacts And Publishing

- Verify files exist before upload; fail before publish if required artifacts are missing.
- Use HTTP upload commands that fail on non-2xx responses, such as `curl --fail-with-body --retry ...` or an equivalent command with checked exit status.
- Generate checksums for binary artifacts and upload them with the package.
- Use GitLab Generic Packages for versioned firmware, SDKs, cross-compiled bundles, changelogs, and checksums when those artifacts must survive beyond short-lived CI artifacts.
- Preserve diagnostic artifacts with `when: always`: metrics JSON, test reports, sanitizer logs, device logs, tar-wrapper logs, and small failure reproducer outputs.
- Keep `expire_in` short for intermediate artifacts and longer for diagnostic artifacts that are needed for incident review.

## Docker And Image Publishing

- Audit local and CI Docker build flags together. `Makefile`, local build scripts, `build`, and `build-mlci` jobs must agree on `--platform`, cache source, `BUILDKIT_INLINE_CACHE`, `--provenance`, `--sbom`, Dockerfile path, secrets, and build args unless a difference is documented.
- Prefer `docker buildx build --platform linux/amd64` when CI images are amd64-only or self-hosted runners vary by host architecture.
- Pre-pull the previous image only as a non-fatal cache warm-up.
- Tag build outputs by commit SHA or pipeline-specific dev tag first. Promote `latest` and semantic/version tags only on the protected default branch.
- Store image versions in a file that both local wrappers and CI read. Do not hard-code image versions in multiple places.
- Keep one canonical registry path variable. Redundant aliases that resolve to the same path make local wrappers and CI jobs drift.
- Check `.dockerignore` with every Dockerfile change; exclude repo metadata, build output, caches, local env files, logs, and unrelated CI artifacts from the build context.
- Split Docker dependency installation by change frequency to preserve layer cache: base packages, toolchain, libraries, large compiled dependencies, Python/test/lint dependencies, then project-specific assets.

## Secret Handling

- Use CI variables, BuildKit `--secret`, BuildKit `--ssh`, and job-token headers instead of `ARG` or literal tokens where possible.
- Never print real token examples in help text or docs. Use placeholders like `<gitlab-token>`.
- Avoid credential-bearing Git URL rewrites. When unavoidable, clean the exact keys that were created and verify with `git config --global --get-regexp`.
- Do not rely on `git config --remove-section url` to remove subsectioned credential rewrites; remove exact `url.<value>.insteadof` keys or match the credential-bearing keys.
- Disable broad command tracing around credentials. If debug logging prints commands, redact token/password/secret/key arguments before output.
- Pin SSH host keys or use `ssh-keyscan` for known controlled hosts. Do not disable host verification globally.

## CI Debugging

- Start from the failed job log, stage, image, runner tag, pipeline source, commit, and exact command.
- Use the project management wrapper first when one exists. For this repo family that is usually `projctl`; run `projctl pipeline-debug` before raw `glab`/API log inspection, do not invent unsupported subcommands, and extend the wrapper when the required operation is truly missing.
- Classify the failure: repository code, CI config, runner capacity, image mismatch, cache corruption, credentials, network, package upload, or device/lab state.
- Reproduce through the project wrapper first. For Dockerized repos, run the same image, platform, mounts, env vars, working directory, and non-interactive command.
- Keep reproductions scoped to the project guidance. If a wrapper supports both targeted and full-tree modes, do not switch to full-tree mode unless the project explicitly allows it.
- Check whether the failing state crosses a GitLab phase boundary. Variables computed in `script` are not automatically available to `after_script`; persist required state in files or artifacts.
- Prefer adding a small validation or preflight check before the expensive step that failed.

Useful official docs to re-check when uncertain:

- GitLab CI YAML reference: https://docs.gitlab.com/ci/yaml/
- GitLab runner configuration: https://docs.gitlab.com/ci/runners/configure_runners/
- GitLab runner advanced configuration: https://docs.gitlab.com/runner/configuration/advanced-configuration/
- GitLab unit test reports: https://docs.gitlab.com/ci/testing/unit_test_reports/
