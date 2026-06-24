---
name: shell
description: Shell implementation and review guidance for safe, portable, maintainable, and supportable scripts. Use when writing, modifying, debugging, or reviewing POSIX sh, Bash, or Zsh scripts, command wrappers, build and CI helpers, installers, process supervision, filesystem automation, and shell tests.
---

# Shell Programming Skill

Treat this file as the shell-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, observability, dependencies, compatibility, and test coverage.

## Dialect And Execution Contract

- Inspect the shebang, file extensions, invocation sites, CI images, supported operating systems, minimum shell versions, formatter and ShellCheck configuration, and project-native commands before editing.
- Choose the narrowest declared dialect: POSIX `sh` for required portability, Bash for arrays or Bash-specific control features, and Zsh only when the project explicitly requires it.
- Do not mix dialects. `[[ ... ]]`, arrays, `local`, process substitution, `pipefail`, and `source` are not portable POSIX syntax.
- Use a shebang only for directly executable scripts. Follow project policy for `/bin/sh`, an absolute interpreter, or `/usr/bin/env`; do not claim a shebang is portable without checking target systems and `PATH` policy.
- Keep sourced libraries free of `main` execution, caller option changes, unconditional `exit`, and global traps unless those effects are their documented API.
- Put executable entry behavior in a `main` function and invoke it with `main "$@"` so parsing and setup remain testable.

## Shell Options And Failure Semantics

- Decide strict-mode behavior explicitly. For new standalone Bash scripts, normally use `set -euo pipefail`, add `-E` only when an `ERR` trap must be inherited, and audit conditionals, command substitutions, pipelines, subshells, and traps for the resulting semantics.
- For POSIX `sh`, use only supported options such as `set -eu`; do not assume `pipefail` exists. For sourced or legacy code, do not add strict options mechanically when doing so changes the caller contract.
- Do not assume `errexit` handles every failure. Check status explicitly where failure is expected, translated, retried, ignored, or used for branching.
- Preserve the failing status before running diagnostics or cleanup. Return the original failure unless cleanup has a documented higher-priority failure contract.
- Use `if command; then ...` or an equivalent explicit branch when success and failure are both valid outcomes.
- Treat every pipeline stage as fallible. Use supported `pipefail`, Bash `PIPESTATUS`, or a pipeline-free structure when an early-stage failure must be observed.
- Never hide a caller-significant failure with `|| true`, a trailing successful command, or an unchecked background job. Explain intentional best-effort behavior.
- Keep function return statuses in the shell range and use stdout only for documented data output; send diagnostics to stderr.

## Expansions, Arguments, And Data

- Quote expansions by default: `"$value"`, `"${items[@]}"`, and `"$@"`. Leave an expansion unquoted only for intentional, reviewed splitting or globbing.
- Use arrays in Bash or Zsh when preserving argument boundaries. Do not construct a command in one string and reparse it.
- Never use `eval` or `sh -c` with data-derived text. Keep code and data separate and pass arguments as distinct words.
- Use `${name}` where adjacent text would make the variable boundary ambiguous. Distinguish unset, empty, and defaulted values intentionally with the appropriate parameter-expansion operator.
- Use `read -r` and set `IFS` locally when parsing delimited input. Do not use a `for` loop over command substitution to read lines.
- Use `printf` for arbitrary or machine-consumed data. Do not rely on implementation-specific `echo` handling of options or escapes.
- Account for command substitution removing trailing newlines. Use a file, delimiter, or another transport when trailing newlines are significant.
- Treat filenames as arbitrary byte sequences except for the NUL and path separator constraints of the platform; do not assume whitespace-free or option-safe names.

## Paths, Files, And Cleanup

- Quote paths and place `--` before untrusted or data-derived operands when the utility supports it.
- Avoid parsing `ls`, human-readable command output, or whitespace-delimited filename lists. Use globs, `find -exec`, null-delimited interfaces when supported, or native shell arrays.
- Create temporary files and directories with a secure project-native mechanism such as `mktemp`; never predict shared temporary names.
- Make cleanup idempotent and register it before the first fallible operation that needs it. Handle `EXIT`, interruption, and termination according to the script contract without deleting resources owned by another process.
- Use a temporary file in the destination filesystem plus an atomic rename when partial output must never become visible.
- Set restrictive permissions or `umask` before creating secret or security-sensitive files; do not rely on fixing permissions afterward.
- Validate paths before destructive operations. Reject empty, root-like, traversal, symlink, and ownership cases according to the boundary contract.

## Processes, Signals, And Concurrency

- Record the PID of every owned background process, observe its exit status with `wait`, and terminate or transfer it explicitly during shutdown.
- Bound parallel jobs and queued work; do not spawn one process per input without a proven limit.
- Forward required signals to children and define shutdown order, timeout, escalation, and final status.
- Do not use broad process-name matching such as `pkill` as an ownership mechanism. Target recorded PIDs or a deliberately created process group.
- Understand subshell boundaries. Do not rely on variable mutations performed in a pipeline component being visible in the parent shell.
- Avoid arbitrary sleeps for readiness. Poll a concrete condition with a deadline or use a process-specific readiness signal.

## Security And Environment

- Validate positional arguments, options, environment variables, paths, identifiers, counts, URLs, and other external inputs before use.
- Parse options with project-standard logic and reject unknown or missing arguments. Use `--` to terminate option parsing where supported.
- Never source an untrusted file or execute text obtained from configuration, network input, filenames, or environment variables.
- Keep `PATH`, locale, current directory, inherited descriptors, and environment dependencies explicit where they affect behavior. Use `command -v` to validate required tools.
- Do not export variables unless child processes require them. Use distinctive names for exported project variables and lowercase names for function-local data.
- Disable or narrowly scope tracing around credentials and sensitive values. Never emit secrets through `set -x`, error messages, command lines, or temporary files.
- Prefer least-privilege commands and reject execution as root unless elevated privilege is part of the explicit contract.

## Portability And Dependencies

- Verify every external utility and option against the supported targets; common GNU extensions are not automatically available on BSD, BusyBox, macOS, or minimal containers.
- Pin or document required interpreter and tool versions when behavior depends on newer features.
- Set locale deliberately for parsing or sorting that requires stable byte-oriented behavior; do not silently override locale when user-facing collation is required.
- Prefer shell builtins and existing project utilities for simple orchestration. Move complex parsing, structured data transformation, or substantial algorithms to a more suitable language.
- Keep generated output deterministic and avoid network access, host-state discovery, or writes outside approved locations unless they are explicit inputs and effects.

## Testing And Verification

- Test scripts through their public command-line contract and test sourced functions only when they are an intentional library boundary.
- Cover empty and missing arguments, whitespace, glob characters, leading hyphens, embedded newlines where supported, command failure, partial output, interrupted cleanup, repeated cleanup, and target-platform differences.
- Isolate environment variables, `PATH`, current directory, temporary files, user configuration, locale, and external commands. Use temporary directories and project-native fake executables.
- Assert exit status, stdout, stderr, filesystem effects, permissions, child-process cleanup, and idempotency rather than only checking that a command ran.
- Use the project's shell test framework, such as Bats or ShellSpec, and keep integration tests separate when they execute real tools or services.
- Run project-native commands first; otherwise use the applicable subset:

```text
sh -n path/to/script.sh
bash -n path/to/script.bash
zsh -n path/to/script.zsh
shellcheck --shell=bash path/to/script
shfmt -d path/to/script
```

- Run syntax and behavior tests under every promised interpreter and supported target environment. Use project-native linting for dialects unsupported by ShellCheck or shfmt, and report tools or platforms that are unavailable.
- Keep ShellCheck suppressions local and explain the actual boundary or invariant immediately above the directive.
