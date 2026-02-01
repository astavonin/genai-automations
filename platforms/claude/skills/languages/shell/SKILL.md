---
name: shell
description: Shell scripting best practices (bash/zsh)
---

# Shell Scripting Skill

## Standards

Follow POSIX conventions where possible, use bash/zsh features when needed.

## Key Principles

### Safety
- Use `set -euo pipefail` at script start
  - `-e`: Exit on error
  - `-u`: Exit on undefined variable
  - `-o pipefail`: Pipeline fails if any command fails
- Quote all variable expansions: `"$variable"`
- Use `[[ ]]` instead of `[ ]` for conditionals

### Code Style
- Use lowercase for local variables
- Use UPPERCASE for environment variables
- Use `${variable}` for clarity in complex expressions
- 2 spaces for indentation
- Use `#!/usr/bin/env bash` for portability

### Error Handling
- Check command exit codes: `if command; then ...`
- Provide meaningful error messages
- Use `trap` for cleanup on exit
- Handle signals appropriately

### Functions
- Use functions for reusable code
- Declare local variables with `local`
- Return status codes, not strings
- Document function purpose

### Best Practices
- Avoid parsing `ls` output (use globs or find)
- Use `$(command)` instead of backticks
- Prefer `[[ ]]` for conditionals
- Use arrays for lists
- Validate inputs and arguments

### Portability
- Use `#!/usr/bin/env bash` for portability
- Avoid bashisms if POSIX compliance needed
- Test on target platforms
- Document required bash version if needed

## Tools

- ShellCheck for linting
- `bash -n script.sh` for syntax checking
- `bash -x script.sh` for debugging

## Example

```bash
#!/usr/bin/env bash
set -euo pipefail

main() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "Error: input required" >&2
        return 1
    fi

    # Process input
    echo "Processing: $input"
}

main "$@"
```

## References

- Google Shell Style Guide
- ShellCheck wiki for common issues
