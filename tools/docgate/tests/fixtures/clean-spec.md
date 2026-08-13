# Appendix Spec — A9 Frozen clean fixture

**Page:** `A9-clean-fixture`
**Dependent articles:** none — this page exists to be verified, not read
**Evidence sources:** the fixture itself
**Device reachable:** yes — `ssh fixturehost.invalid`
**Status:** Draft

---

## 1. Scope

### Concepts carried

- Nothing. Every row below is correct, so an acceptance run over this file reports zero `FAIL` rows.

---

## 2. Claims

| ID | Claim | Source | Verified by |
|----|-------|--------|-------------|
| C1 | The fixture host reports itself as `fixturehost` | on-device measurement | V1 |
| C2 | The fixture kernel release is `6.12.47-fixture` | on-device measurement | V1 |
| C3 | The buffer count settles at `4 buffers` after the sweep | on-device measurement | V2 |
| C4 | Two probes run in one shell, and the second sees `stage two` | on-device measurement | V3 |
| C5 | A probe whose command exits non-zero still records `Inappropriate ioctl for device` | on-device measurement | V4 |
| C6 | The ring buffer is cleared before the mode is read, and the mode reads `mode: burst` | on-device measurement | V5 |
| C7 | A Conclusion quoting nothing checks nothing, and the row still runs | on-device measurement | V6 |
| C8 | The documented flag `FIXTURE_CAP_ALPHA` carries the value `0x20000000` | fixture documentation | V7 |
| C9 | The documented rule names `one input and one output` | fixture documentation | V7 |
| C10 | The vendor page states the throttle onset temperature | vendor web page | V8 |
| C11 | The kernel source path decides where `link_validate` is called | kernel source | V9 |

**Unverified claims.** Carried, not softened.

| ID | Claim | What is missing |
|----|-------|-----------------|
| C12 | A second board behaves the same way | `[UNVERIFIED: no second board]` |

---

## 3. Source Requirements

- **SR6:** The claimed value or token appears literally in the §5 captured output.
- **SR7:** Every §5 row records all six fields.
- **SR8:** Every claim ID appears in exactly one §2 table, and every `Verified by` names a §5 row whose `Establishes` lists that ID.

---

## 4. Terminology Contract

### `fixture row`

**Definition:** One `### V<N>` block carrying six fields, its commands and its captured output.
**Used by:** the acceptance run
**Invariants:**
- Every row below is correct.

---

## 5. Verification Procedure

Every row ran on 2026-08-11 against the fixture host, reached over `ssh fixturehost.invalid`.

### V1 — Host identity and kernel release

**Establishes:** C1, C2
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
hostname; uname -r
```

    fixturehost
    6.12.47-fixture

**Conclusion:** `fixturehost` and `6.12.47-fixture` are the host and kernel every other row ran against.

### V2 — Buffer count after the sweep, with interior blank lines

**Establishes:** C3
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'probing\n\n4 buffers\n'
```

    probing

    4 buffers

**Conclusion:** The blank line between the two output lines is interior to one block, and `4 buffers` is the settled count.

### V3 — Two command blocks sharing one shell

**Establishes:** C4
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
stage=two
```

Between the two blocks sits prose, and the row carries two output blocks against two command blocks.

    stage one

```bash
printf 'stage %s\n' "$stage"
```

    stage two

**Conclusion:** `stage two` proves the second block saw the variable the first set, so the row is piped to one shell rather than run block by block.

### V4 — A command whose non-zero exit is the evidence

**Establishes:** C5
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'VIDIOC_G_PARM: failed: Inappropriate ioctl for device\n'
false
```

    VIDIOC_G_PARM: failed: Inappropriate ioctl for device

**Conclusion:** `Inappropriate ioctl for device` is `ENOTTY`, and the failing exit status is the result rather than a transport problem.

### V5 — Ring buffer cleared before the mode is read

**Establishes:** C6
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** mutating — clears the kernel ring buffer

```bash
sudo dmesg -C
printf 'mode: burst\n'
```

    mode: burst

**Conclusion:** `mode: burst` is the configured mode, read after the ring buffer was cleared.

### V6 — A Conclusion that quotes nothing

**Establishes:** C7
**Method:** on-device
**Ran on:** fixture board via `ssh fixturehost.invalid`
**Run date:** 2026-08-11
**Side effects:** none

```bash
printf 'nothing quoted here\n'
```

    nothing quoted here

**Conclusion:** The row runs and its token set is empty, so it passes on transport alone and contributes no token to the count.

### V7 — Documented capability flag and its rule

**Establishes:** C8, C9
**Method:** documentation lookup
**Ran on:** authoring host, `docs/fixture-caps.rst` from `fixture.invalid/repo` branch `fixture-branch`, table "Capability Flags"
**Run date:** 2026-08-11
**Side effects:** none

```bash
grep -A4 FIXTURE_CAP_ALPHA docs/fixture-caps.rst
```

        * - ``FIXTURE_CAP_ALPHA``
          - 0x20000000
          - There is only one input and one output seen from userspace.

A second passage from the same file follows, so this row carries one command block against two output blocks.

    The rule is stated once and quoted twice.

**Conclusion:** `0x20000000` and `one input and one output` are the definition C8 and C9 bind §4 to.

### V8 — Vendor documentation page

**Establishes:** C10
**Method:** documentation lookup
**Ran on:** authoring host, `https://vendor.example/docs/thermal.html`, section "Thermal control"
**Run date:** 2026-08-11
**Side effects:** none

```bash
# WebFetch of the vendor documentation page
```

    "The cores are throttled back at 80 degrees."

**Conclusion:** The quoted sentence gives `80 degrees` as the onset of throttling.

### V9 — Kernel source lookup

**Establishes:** C11
**Method:** kernel source
**Ran on:** authoring host, `drivers/media/mc/mc-entity.c` from `fixture.invalid/repo` branch `fixture-branch`
**Run date:** 2026-08-11
**Side effects:** none

```bash
grep -n link_validate drivers/media/mc/mc-entity.c
```

    457:            ret = entity->ops->link_validate(link);

**Conclusion:** `link_validate` has one call site, and no resolver claims this `Method:` value.
