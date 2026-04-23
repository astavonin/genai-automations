# Linter Suppression Guidelines

## Critical Rule

Always explain why a suppression is necessary.

## Why This Matters

- Future readers need to know why the rule was bypassed.
- Suppression comments make review and audit easier.
- Explanations reduce cargo-cult copy-pasting.
- Requiring justification keeps technical debt visible.

## Good Explanations

Good explanations are:
- specific about the real constraint
- narrow enough to justify the exact suppression
- actionable when the suppression is temporary

Examples:

```cpp
// NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast): Hardware register access requires reinterpret_cast
auto* reg = reinterpret_cast<volatile uint32_t*>(address);
```

```python
result = api_call()  # type: ignore[no-untyped-call]  # Third-party package has no type stubs
```

```go
//nolint:gosec // MD5 is used only for non-cryptographic fixture checksums
hash := md5.New()
```

## Format By Language

### C++

```cpp
// NOLINTNEXTLINE(rule-name): reason
code();
```

### Python

```python
# noqa: rule-name - reason
code()

value = call()  # type: ignore[error-code]  # reason
```

### Go

```go
//nolint:rule-name // reason
code()
```

## When Suppressions Are Acceptable

Suppressions are usually acceptable for:
- hardware or low-level constraints
- external protocol or specification constants
- required API boundary compatibility
- third-party library limitations
- justified legacy debt with a follow-up reference

## Fix Instead Of Suppress When

- the warning points to a real design issue
- the fix is as easy as the suppression
- the same rule is being suppressed repeatedly
- a simpler rewrite would remove the need entirely

## Review Expectations

When reviewing suppressions, check that:
- the explanation still matches reality
- the scope is as narrow as possible
- the code is not hiding a correctness, safety, or maintainability issue
