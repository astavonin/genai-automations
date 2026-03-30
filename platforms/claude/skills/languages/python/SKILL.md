---
name: python
description: Python coding standards based on PEP 8 and Google Python Style Guide. Use when writing, reviewing, or modifying Python code to apply type hints, docstrings, and Pythonic patterns.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: languages
  tags: [python, programming]
---

# Python Programming Skill

## Standards

**Follow PEP 8:**
- https://peps.python.org/pep-0008/

**Follow Google Python Style Guide:**
- https://google.github.io/styleguide/pyguide.html

## Key Principles

### Code Style
- 4 spaces for indentation (never tabs)
- Maximum line length: 79 characters (code), 72 (docstrings/comments)
- Use snake_case for functions and variables
- Use PascalCase for classes
- Use UPPER_CASE for constants

### Type Hints
- Use type hints for function signatures
- Use `typing` module for complex types
- Run mypy for type checking

### Documentation
- Use docstrings for modules, classes, and functions
- Follow Google or NumPy docstring format
- Keep docstrings concise and clear

### Pythonic Patterns
- Use list comprehensions where appropriate
- Prefer context managers (`with` statement)
- Use generators for large datasets
- Leverage standard library

### Error Handling
- Use specific exception types
- Avoid bare `except:` clauses
- Use `finally` for cleanup
- Prefer `with` for resource management

### Testing
- Use pytest for unit tests
- Follow AAA pattern (Arrange, Act, Assert)
- Use fixtures for common setup
- Test edge cases and error conditions

## Formatting

Apply black or autopep8 for automatic formatting.

## Static Analysis

Run pylint and mypy for code quality and type checking.

## References

- PEP 8: https://peps.python.org/pep-0008/
- Google Python Style Guide: https://google.github.io/styleguide/pyguide.html
