# Comment Philosophy

## Core Principle

Write self-documenting code that needs minimal comments.

## Before Adding a Comment

Ask yourself:
1. Can I rename variables, functions, or types to make this clearer?
2. Can I extract this into a well-named helper?
3. Can I simplify the control flow?
4. Is the comment explaining intent or just translating the code?

## When Comments Are Necessary

Use comments for:
- non-obvious design intent
- complex algorithms where the approach is not immediately clear
- TODOs with enough context to be actionable
- tests where the scenario would otherwise be hard to follow
- public API doc comments when the language or project expects them

## Test Comments

For tests, comments should explain the scenario being exercised, not narrate each line.

Integration tests that run real components or multi-step flows may use a short numbered step list near the top of the test body:

```python
def test_clean_exit() -> None:
    # 1. Start the manager and load the fixture configuration.
    # 2. Launch the child processes and wait for steady state.
    # 3. Stop each process and verify a clean exit status.
    ...
```

Rules:
- steps describe logical behavior, not code mechanics
- each step is one line
- order matches execution order
- omit setup and teardown details handled elsewhere

## What Not To Comment

Do not use comments for:
- usage examples that should live in tests or docs
- complexity disclaimers that should be solved by refactoring
- responsibility lists that code structure should already show
- obvious restatements of what the code already says

## Summary

Comments are for insight, intent, and exceptions. Clear code should carry the routine explanation on its own.
