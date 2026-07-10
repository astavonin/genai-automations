# Implementation Output Contract

Return JSON that captures:
- `final_status`
- `summary`
- `files_changed`
- `verification_results`
- `reasoning`
- `open_issues`

Do not wrap the JSON in Markdown.

## On-Device Verification Reporting

When the design doc's `On-Device Verification` field requires on-device verification:
- If verification ran and passed: add a `verification_results` entry with `"command": "<entry-point>"`, `"status": "PASSED"`, and `"details": "<summary>"`.
- If verification ran and failed: add a `verification_results` entry with `"status": "FAILED"` and failure details.
- If no device is available: add to `open_issues`: `"On-Device Verification: BLOCKED — <reason>"`.
- If the field contains `on-device scope: NO`: no entry needed; skip silently.
- If the field is absent from the design doc entirely: add to `open_issues`: `"On-Device Verification: BLOCKED — On-Device Verification field missing from design doc."`.
