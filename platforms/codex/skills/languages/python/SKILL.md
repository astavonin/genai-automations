---
name: python
description: Python coding standards based on PEP 8 and the Google Python Style Guide. Use when writing, reviewing, or modifying Python code to apply type hints, docstrings, and idiomatic Python patterns.
---

# Python Programming Skill

## Standards

Follow:
- PEP 8: https://peps.python.org/pep-0008/
- Google Python Style Guide: https://google.github.io/styleguide/pyguide.html

## Key Principles

### Code Style
- Use 4 spaces for indentation
- Use `snake_case` for functions and variables
- Use `PascalCase` for classes
- Use `UPPER_CASE` for constants

### Type Hints
- Add type hints to public and non-trivial function signatures
- Use `typing` constructs for complex types
- Run project type checking such as `mypy` or `pyright` when configured

### Documentation
- Use concise docstrings for modules, classes, and functions where they add value
- Follow the project's docstring format consistently

### Pythonic Patterns
- Prefer context managers for resource handling
- Use comprehensions when they stay readable
- Use generators for large or streaming data
- Prefer standard library solutions before new dependencies

### Error Handling
- Raise specific exception types
- Avoid bare `except:`
- Use `finally` only when cleanup cannot be expressed with a context manager

## Workflow

- Format with the project's Python formatter, typically `black`
- Run configured lint and type-check tools
- Use `testing` and `code-quality` skills alongside this skill when writing or reviewing code

## References

- PEP 8: https://peps.python.org/pep-0008/
- Google Python Style Guide: https://google.github.io/styleguide/pyguide.html
