# External Implementation Workflow

The request document is a design document.

Execution contract:
- `Repository`
- `Functional Requirements`
- `Non-Functional Requirements`
- `Constraints`
- `Verification`
- `On-Device Verification`
- `Observed-Failure Ledger`
- `Context Files`

Use the full request for context, but treat the implementation-context fields as authoritative.

When the On-Device Verification field is present and does not contain `on-device scope: NO`, on-device verification is a required step:
- If a device is reachable: run the `**Entry point:**` command and add a `verification_results` entry with `"command": "<entry-point>"`, `"status": "PASSED"`, and `"details": "<summary>"`.
- If no device is available: add to `open_issues`: `"On-Device Verification: BLOCKED — <reason>"`.
- If the field contains `on-device scope: NO`: skip silently, no entry needed.
- If the field is absent from the design doc: add to `open_issues`: `"On-Device Verification: BLOCKED — On-Device Verification field missing from design doc."`

## Observed-Failure Regression Test

The `Observed-Failure Ledger` field states whether this work fixes a failure that already
happened. Treat it as the trigger:

- **Field present with an `**Status:** open` entry** — a regression test for that failure is a
  required deliverable of this run. Record it in `verification_results`. If you cannot write
  one, add to `open_issues`: `"Regression test: BLOCKED — <why>"`; do not report success without
  either.
- **Field absent** — treat this as new work. If the design nonetheless describes repairing a
  failure that occurred, the rule below still applies.


When the implementation fixes a failure that **actually happened** — a red CI job, an on-device or deployment failure, a runtime crash or hang, a manual-testing defect, a bug report, a flaky test, or a review finding confirmed to reproduce — the fix and a test reproducing that failure are **one deliverable**. A fix alone is incomplete and will be rejected downstream.

- **Write the test first.** Run it against the unfixed code and confirm it fails for the observed reason, then apply the fix and confirm it passes. Record both outcomes in `verification_results`. Where reverting is impracticable (device state, destructive setup), say so plainly instead of reporting a red result you did not observe.
- **Default to integration coverage.** Observed failures are usually composition failures — the units worked, their interaction did not. A unit test that mocks the exact boundary the bug crossed re-encodes the bug's assumption instead of catching it. Use a unit test only when the failure was reproducible from isolated logic with the inputs in hand.
- **Assert the actual symptom,** not a proxy or an adjacent happy path. Ask: would this test have caught the reported failure?
- **Name the test after the behaviour,** never the incident — `test_deploy_fails_fast_on_unset_version`, not `test_issue_42_regression`.
- **Never defer it.** If you believe the failure genuinely cannot be tested, do not decide that yourself: add to `open_issues`: `"Regression test: BLOCKED — <why it cannot be reproduced>"`.
