# Linter Suppression Guidelines

## Critical Rule

**ALWAYS add a comment explaining WHY when suppressing linter warnings.**

## Why This Matters

1. **Maintainability:** Future developers need to know why the rule was suppressed
2. **Safety:** Prevents cargo-cult copy-pasting of suppressions
3. **Review:** Makes code review easier by showing intent
4. **Audit:** Helps identify technical debt and refactoring opportunities

## Format by Language

### C++ (clang-tidy, cppcheck)

```cpp
// NOLINTNEXTLINE(rule-name): Explanation why suppression needed
problematic_code();

// NOLINT: Brief explanation (suppresses all rules for this line)
problematic_code(); // NOLINT

// NOLINTNEXTLINE(rule1,rule2): Multiple rules
code();
```

**Examples:**
```cpp
// NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast): Hardware register requires reinterpret_cast
auto* reg = reinterpret_cast<volatile uint32_t*>(HW_ADDR);

// NOLINTNEXTLINE(cppcoreguidelines-avoid-magic-numbers): Protocol constant from spec
constexpr int kMagicValue = 0x1234;

// NOLINTNEXTLINE(modernize-use-auto): Explicit type for API clarity
const std::vector<int> results = getResults();
```

### Python (flake8, pylint, mypy)

```python
# noqa: rule-name - explanation
code()  # noqa: E501 - Long line unavoidable due to URL

# type: ignore[error-type]  # explanation
variable = function()  # type: ignore[no-untyped-call]  # Third-party lib lacks types

# pylint: disable=rule-name  # explanation
# pylint: enable=rule-name   # re-enable after section
```

**Examples:**
```python
# pylint: disable=too-many-arguments  # Constructor mirrors DB schema
def __init__(self, id, name, email, phone, address, city, state, zip):
    pass

result = api_call()  # type: ignore[no-untyped-call]  # Legacy API without stubs

long_url = "https://..."  # noqa: E501 - URL cannot be split
```

### Go (golint, staticcheck)

```go
//nolint:rule-name // explanation
code()

//nolint:rule1,rule2 // explanation for multiple
code()

//nolint // suppress all (use sparingly)
code()
```

**Examples:**
```go
//nolint:gocyclo // Legacy function, refactor scheduled in issue-456
func complexLegacyCode() {
    // ...
}

//nolint:gosec // MD5 used for non-cryptographic checksums only
hash := md5.New()
```

### Rust (clippy)

```rust
#[allow(clippy::rule_name)]  // explanation
fn function() {
    // ...
}

// For single item:
#[allow(clippy::cast_lossless)]  // Explicit cast for API boundary
let x = value as u32;
```

**Examples:**
```rust
#[allow(clippy::too_many_arguments)]  // Mirrors C API signature
pub fn legacy_api(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) {
    // ...
}

#[allow(clippy::unwrap_used)]  // Test code only, panic acceptable
#[cfg(test)]
fn test_helper() {
    let value = parse("123").unwrap();
}
```

### JavaScript/TypeScript (ESLint)

```javascript
// eslint-disable-next-line rule-name -- explanation
code();

/* eslint-disable rule-name */
// Multiple lines
/* eslint-enable rule-name */

// @ts-ignore: explanation
code();
```

**Examples:**
```typescript
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- Third-party API returns any
function process(data: any) {
    // ...
}

// @ts-ignore: Legacy library without types
import * as legacy from 'legacy-lib';
```

## Good Explanations

### What Makes a Good Explanation?

- **Specific:** Explains the exact reason, not generic
- **Justifiable:** Shows the suppression is necessary
- **Actionable:** Indicates if it's temporary (with issue reference)

### Examples

**Good:**
```cpp
// NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access): Protocol requires union for memory efficiency
```

**Bad:**
```cpp
// NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access): Need to use union here
```

**Good:**
```python
# type: ignore[attr-defined]  # Dynamic attribute added by metaclass
```

**Bad:**
```python
# type: ignore  # Mypy doesn't understand this
```

**Good:**
```rust
#[allow(clippy::match_wild_err_arm)]  // Error type is opaque third-party, no useful info
```

**Bad:**
```rust
#[allow(clippy::match_wild_err_arm)]  // Match is fine
```

## When Suppressions Are Acceptable

1. **Hardware/Low-level:** Unavoidable casts, volatile access
2. **Protocol/Spec:** Magic numbers defined by external specification
3. **API Boundary:** Matching external API signature
4. **Performance:** Justified optimization (with benchmark reference)
5. **Third-party:** Limitations in external libraries
6. **Legacy:** Technical debt (with refactor issue reference)

## When to Fix Instead of Suppress

1. **Code smell:** If the warning points to genuine design issue
2. **Easy fix:** If suppression takes same effort as fixing
3. **Pattern:** If multiple suppressions for same rule
4. **Unnecessary:** If code can be rewritten without suppression

## Audit Suppressions

Periodically search for suppressions:
```bash
# Find all C++ suppressions
grep -r "NOLINTNEXTLINE\|NOLINT" .

# Find all Python suppressions
grep -r "noqa\|type: ignore\|pylint: disable" .

# Find Rust suppressions
grep -r "#\[allow" .
```

Review each to ensure:
- Explanation is still valid
- Suppression is still necessary
- No better solution available now
