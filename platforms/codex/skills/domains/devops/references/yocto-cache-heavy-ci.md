# Yocto And Cache-Heavy CI

Use this reference for Yocto, Buildroot, SDK, firmware, cross-compilation, or other long-running embedded builds where cache correctness dominates pipeline cost.

## Core Pattern

- Make one shared runner script the source of truth for the expensive build. Local and CI should call the same script with different environment defaults.
- Prefer direct execution inside the prepared build image over nested Docker when possible. Keep DinD as a fallback only when the build contract requires Docker.
- Fail early before starting the multi-hour build: validate cache visibility, write permissions, symlinks, image contents, credentials, toolchain activation, and expected output paths.
- Keep the runtime user model aligned between local and CI. Do not chase non-root execution if the vendor SDK requires root-owned writes and the workaround is slower or more fragile than the risk.

## Cache Architecture

Separate cache domains:

- downloads/source cache
- Yocto `sstate-cache`
- compiler cache such as `ccache`
- final build output and SDK artifacts

Rules:

- Log cache sizes and hit/miss state before the build.
- Verify cache integrity before the expensive build. Check for zero-byte/truncated downloads and format-specific health markers such as Yocto sstate `.siginfo` files.
- Treat a corrupt cache differently from an empty cache: fail or quarantine corruption instead of silently reusing it.
- Cap cache size with deterministic eviction. LRU by mtime is acceptable when the cache format has many independent files.
- Avoid recursive `chown -R` or other whole-cache rewrites on tens of gigabytes. Set permissions at restore boundaries and verify write access.
- Exclude non-atomic cache directories from rsync or shared cache mutation. For Yocto downloads, bare `git2/` directories are risky because interrupted transfer can leave a poisoned bare repo; prefer atomic tarballs or files that BitBake can re-expand.
- Use `--partial` and `--append-verify` for large rsync transfers when interruption is likely, but combine them with retries and integrity checks.
- Omit compression for already-compressed Yocto downloads when CPU cost outweighs transfer savings.
- Use SSH keepalive and bounded retries for cache-server sync.

## Symlinks And Bind Mounts

- Remove a directory target before replacing it with a symlink. `ln -sfn source target` can create `target/source` when `target` is an existing directory.
- After creating cache symlinks, verify both the symlink path and the direct bind-mount path see the same writes.
- Use a sustained write test, not just `mkdir/rmdir`. Write multiple real files through the symlink and count them from the direct mount path.
- If the build runs as a non-root user, repeat the write test as that user.
- Abort before the expensive build when cache writes land in the container overlay rather than the host or cache mount.

## Ownership And Extraction

- Archive ownership can break in user-namespaced CI runners. Prefer fixing extraction flags such as `--no-same-owner` at the correct boundary.
- If a tar wrapper is used, keep it narrow, log its invocations, and preserve the log as a diagnostic artifact.
- Align image build UID/GID with vendor SDK expectations only when needed. Handle pre-existing groups before `groupadd`.
- Avoid silent ownership repair paths that hide the actual failure or take longer than rebuilding the affected cache.

## Long-Running Build Controls

- Use `resource_group` to serialize jobs that consume hundreds of gigabytes or mutate shared cache state.
- Use `interruptible` for branch builds that can be canceled safely on newer commits.
- Do not retry clean-build timeouts by default. Retry runner system failures, not deterministic 12-hour build timeouts.
- Track start time in a file when `after_script` needs it. Do not depend on shell variables surviving GitLab phase boundaries.
- Emit build metrics as JSON: duration, branch, commit, pipeline ID, execution mode, cache hit rate, artifact sizes.
- Preserve metrics and diagnostic logs with `artifacts: when: always`.

## Periodic Cache Checkpointing

For builds where useful cache entries are produced before the final job result:

- Run a monitor process in the CI shell before the build starts.
- Let the monitor inherit SSH agent and CI variables from setup.
- Every interval, log cache size and hit/miss stats.
- Sync useful atomic cache domains incrementally. A failed monitor sync must log and continue; it must not kill the build.
- Keep final `after_script` sync authoritative: trim, retry, save, then evict on the remote cache server.
- Keep CI cache-server concerns out of the pure build runner when doing so preserves local-CI parity.

## Artifacts

- Make firmware or primary output required unless the job contract explicitly says otherwise.
- Treat SDK installers or full build-output tarballs as optional only on branches where that is acceptable; make them required on release/default branch when downstream jobs need them.
- Name artifacts with the same version formula used by build, publish, and downstream jobs.
- Generate checksums after all required artifacts are present.
- Upload firmware, SDK, changelog, metrics, and checksums to Generic Packages when they are release evidence or downstream inputs.
- Keep CI artifacts small and diagnostic; do not move 60-90 GB caches through artifacts between stages.

## Docker Image Build For SDK Repos

- Layer large vendor repo sync steps by change frequency and size to survive network interruptions and reuse completed layers.
- Use BuildKit `--ssh` for private SSH repositories and `--secret` for tokens.
- After private sync, scrub credential-bearing Git config and manifest files. Verify that no token-bearing URL rewrites remain.
- Add an image verification step at the end of the Dockerfile to check expected SDK directories, manifest repos, layer/config patches, tool versions, duplicate-name repo paths, and image size.

## Review Checklist

- Is there one shared local/CI runner path?
- Are cache paths, symlinks, and permissions verified before the long build?
- Are cache corruption checks explicit, including truncated downloads and sstate signature/health markers?
- Are non-atomic cache directories excluded or otherwise protected?
- Are cache restore, build, periodic sync, final save, and eviction responsibilities separated?
- Are runner disk limits and serialization explicit?
- Are long timeouts not retried blindly?
- Are artifact paths discovered robustly instead of hard-coded to one machine name?
- Are upload commands checked for HTTP failure and retried?
- Is credential cleanup verified, not assumed?
