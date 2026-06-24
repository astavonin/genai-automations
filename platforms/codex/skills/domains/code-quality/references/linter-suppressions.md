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

```rust
#[expect(clippy::too_many_arguments, reason = "signature mirrors the stable C ABI")]
pub unsafe extern "C" fn register_callback(/* ... */) { /* ... */ }
```

```bash
# The SDK path comes from the validated toolchain manifest.
# shellcheck disable=SC1090
. "$sdk_env"
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

### Rust

```rust
#[expect(clippy::lint_name, reason = "specific reason")]
fn item() {}
```

Prefer `#[expect]` for a known local violation because Rust warns when the expected lint is no longer emitted. Use narrowly scoped `#[allow(..., reason = "...")]` only when the lint may legitimately be absent in some supported configuration or when a persistent project policy requires it.

### Shell

Place a concrete reason immediately above the narrowest ShellCheck directive:

```bash
# The SDK path comes from the validated toolchain manifest.
# shellcheck disable=SC1090
. "$sdk_env"
```

Prefer a directive on one command or function over a file-wide disable. Specify the analyzed dialect when ShellCheck cannot infer it safely.

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
