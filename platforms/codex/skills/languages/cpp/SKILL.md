---
name: cpp
description: C++ Core Guidelines and best practices
---

# C++ Programming Skill

## Standards

**Strictly follow The C++ Core Guidelines:**
- https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines

## Key Principles

### Modern C++
- Use RAII for resource management
- Prefer smart pointers over raw pointers
- Use STL containers and algorithms
- Prefer `auto` for type deduction where it improves readability
- Use `constexpr` for compile-time evaluation

### Safety
- Avoid undefined behavior
- Use proper const correctness
- Initialize all variables
- Avoid C-style casts (use static_cast, dynamic_cast, etc.)
- Use range-based for loops

### Code Organization
- Header guards or `#pragma once`
- Minimize header dependencies
- Forward declarations where possible
- Keep header files clean and minimal

### Error Handling
- Use exceptions for exceptional cases
- RAII ensures cleanup even with exceptions
- Prefer standard exception types
- Document exception specifications

### Performance
- Pass large objects by const reference
- Use move semantics where appropriate
- Avoid unnecessary copies
- Profile before optimizing

## Formatting

Apply clang-format using project configuration.

## Static Analysis

Run clang-tidy for code quality checks.

## References

See `references/` directory for detailed guidelines and patterns.
