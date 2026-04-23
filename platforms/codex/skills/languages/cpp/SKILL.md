---
name: cpp
description: C++ coding standards based on the C++ Core Guidelines. Use when writing, reviewing, or modifying C++ code to apply RAII, const correctness, memory safety, and modern C++ patterns.
---

# C++ Programming Skill

## Standards

Strictly follow the C++ Core Guidelines:
- https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines

## Key Principles

### Modern C++
- Use RAII for resource management
- Prefer smart pointers over raw pointers
- Use STL containers and algorithms
- Prefer `auto` where it improves readability
- Use `constexpr` for compile-time evaluation
- Prefer static polymorphism over dynamic where practical

### Safety
- Avoid undefined behavior
- Use proper const correctness
- Initialize all variables
- Avoid C-style casts; use `static_cast`, `dynamic_cast`, and related casts explicitly
- Prefer range-based loops when they improve clarity

### Code Organization
- Use header guards or `#pragma once`
- Minimize header dependencies
- Forward declare where it meaningfully reduces coupling
- Keep headers narrow and readable

### Error Handling
- Use exceptions for exceptional cases when the project uses them
- Let RAII own cleanup
- Prefer standard exception types unless domain-specific errors are required

### Performance
- Pass large objects by const reference unless ownership transfer is intended
- Use move semantics where appropriate
- Avoid unnecessary copies
- Profile before optimizing

## Workflow

- Format with the project's C++ formatter, typically `clang-format`
- Run available static analysis, typically `clang-tidy`
- Use `testing` and `code-quality` skills alongside this skill when writing or reviewing code

## References

- C++ Core Guidelines: https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
