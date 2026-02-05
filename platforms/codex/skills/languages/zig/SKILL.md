---
name: zig
description: Zig Style Guide and best practices
---

# Zig Programming Skill

## Standards

**Follow Zig Style Guide:**
- https://ziglang.org/documentation/master/#Style-Guide

## Key Principles

### Code Style
- 4 spaces for indentation
- camelCase for functions and variables
- PascalCase for types
- SCREAMING_SNAKE_CASE for constants
- Use `zig fmt` for formatting

### Memory Management
- Explicit allocation, no hidden control flow
- Pass allocators explicitly
- Use defer for cleanup
- RAII-style resource management
- No automatic memory management

### Error Handling
- Use error unions: `!T` or `ErrorSet!T`
- Use `try` to propagate errors
- Use `catch` to handle errors
- Define custom error sets
- Errors are values

### Compile-Time Execution
- Leverage comptime for code generation
- Use comptime parameters for generic code
- Type reflection at compile time
- No runtime overhead for abstractions

### Safety
- Debug mode checks by default
- Undefined behavior is detectable
- No null pointers (use optionals)
- Bounds checking in debug mode

### Testing
- Use `test` blocks
- Run with `zig test`
- Test at compile time when possible

## Formatting

Run `zig fmt` automatically.

## References

See Zig documentation and language reference.
