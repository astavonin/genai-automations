# External Implementation Workflow

The request document is a design document.

Execution contract:
- `Repository`
- `Functional Requirements`
- `Non-Functional Requirements`
- `Constraints`
- `Verification`
- `On-Device Verification`
- `Context Files`

Use the full request for context, but treat the implementation-context fields as authoritative.

When the On-Device Verification field is present and does not contain `on-device scope: NO`, on-device verification is a required step:
- If a device is reachable: run the `**Entry point:**` command and add a `verification_results` entry with `"command": "<entry-point>"`, `"status": "PASSED"`, and `"details": "<summary>"`.
- If no device is available: add to `open_issues`: `"On-Device Verification: BLOCKED — <reason>"`.
- If the field contains `on-device scope: NO`: skip silently, no entry needed.
- If the field is absent from the design doc: add to `open_issues`: `"On-Device Verification: BLOCKED — On-Device Verification field missing from design doc."`
