# Appendix Spec — A8 Frozen defect fixture

**Page:** `A8-defect-fixture`
**Dependent articles:** none — this page exists to be failed
**Evidence sources:** the fixture itself
**Device reachable:** yes — `ssh fixturehost.invalid`
**Status:** Draft

---

## 1. Scope

### Concepts carried

- One instance of every failure mode, so a run over this file enumerates them exactly.

---

## 2. Claims

| ID | Claim | Source | Verified by |
|----|-------|--------|-------------|
| C1 | A row carrying no `Side effects:` field fails | on-device measurement | V1 |
| C2 | A row reading bare `mutating` fails | on-device measurement | V2 |
| C3 | A row reading `partial` fails | on-device measurement | V3 |
| C4 | A row carrying no `Conclusion:` fails | on-device measurement | V4 |
| C5 | A placeholder `Run date:` fails | on-device measurement | V5 |
| C6 | A `Run date:` that is not `YYYY-MM-DD` fails | on-device measurement | V6 |
| C7 | An empty `Ran on:` fails | on-device measurement | V7 |
| C8 | A gap in the row IDs fails against the row after it | on-device measurement | V9 |
| C9 | A `Verified by` naming no §5 row is a graph break | on-device measurement | V50 |
| C10 | A `Verified by` whose row omits the claim is a graph break | on-device measurement | V11 |
| C11 | An empty `Verified by` cell is a graph break | on-device measurement |  |

**Repeated claims.** This table exists so one ID appears in two §2 tables carrying the column.

| ID | Claim | Source | Verified by |
|----|-------|--------|-------------|
| C1 | The same ID again, which SR8's uniqueness clause forbids | on-device measurement | V1 |

---

## 3. Source Requirements

- **SR7:** Every §5 row records all six fields.
- **SR8:** Every claim ID appears in exactly one §2 table.

---

## 4. Terminology Contract

### `defect row`

**Definition:** A `### V<N>` block carrying exactly one failure mode.
**Used by:** the defect run
**Invariants:**
- Each row below fails for one stated reason.

---

## 5. Verification Procedure

### V1 — No `Side effects:` field

**Establishes:** C1
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11

```bash
printf 'alpha\n'
```

    alpha

**Conclusion:** `alpha` is the token this row would check if it carried the sixth field.

### V2 — Bare `mutating` with no tail

**Establishes:** C2
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** mutating

```bash
printf 'beta\n'
```

    beta

**Conclusion:** `beta` is the token, and the field says what class the row is in without saying what changes.

### V3 — `Side effects:` outside the closed set

**Establishes:** C3
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** partial

```bash
printf 'gamma\n'
```

    gamma

**Conclusion:** `gamma` is the token, and `partial` is neither legal value.

### V4 — No `Conclusion:` field

**Establishes:** C4
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'delta\n'
```

    delta

### V5 — Placeholder `Run date:`

**Establishes:** C5
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** <YYYY-MM-DD>
**Side effects:** none

```bash
printf 'epsilon\n'
```

    epsilon

**Conclusion:** `epsilon` is the token, and the date was never substituted.

### V6 — `Run date:` in the wrong shape

**Establishes:** C6
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-8-1
**Side effects:** none

```bash
printf 'zeta\n'
```

    zeta

**Conclusion:** `zeta` is the token, and the date is not zero-padded.

### V7 — Empty `Ran on:`

**Establishes:** C7
**Method:** on-device
**Ran on:**
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'eta\n'
```

    eta

**Conclusion:** `eta` is the token, and the row records no host at all.

### V9 — First row after the gap

**Establishes:** C8
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'theta\n'
```

    theta

**Conclusion:** `theta` is the token, and V8 is absent — deleted without renumbering.

### V9 — The same ID again, in place

**Establishes:** C8
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'iota\n'
```

    iota

**Conclusion:** `iota` is the token, and this ID duplicates the row above rather than following it.

### V10 — `Establishes:` naming no §2 claim

**Establishes:** C99
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'kappa\n'
```

    kappa

**Conclusion:** `kappa` is the token, and C99 is in no §2 table.

### V11 — A row a claim points at wrongly

**Establishes:** C11
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'lambda\n'
```

    lambda

**Conclusion:** `lambda` is the token, and C10 names this row while this row's `Establishes:` does not name C10.
