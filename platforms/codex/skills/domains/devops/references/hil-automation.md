# HIL And On-Device Automation

Use this reference for hardware-in-the-loop jobs, ADB/SSH device workflows, on-device validation, firmware flashing, OTA scenarios, lab runners, and verification CLIs.

## CI Contract

- Give every HIL job an explicit runner tag that maps to the required lab or device class.
- Use `resource_group` for each physical device, bench, flashing station, or exclusive lab resource.
- Use protected runners and protected variables for jobs that can access devices, credentials, firmware signing keys, or private networks.
- Make destructive jobs manual or default-branch/protected-only unless the project explicitly allows branch-triggered flashing.
- Set job-level `timeout` and, when supported by the runner, script/after-script timeouts so cleanup and artifact upload still run.
- Run HIL jobs in non-interactive mode. CI must not require viewers, TTY, manual prompts, or `-it`.

## Entry Points

- Provide one stable CLI entry point for device verification.
- Support at least: `--ci`, `--scenario`, `--serial`, `--timeout`, `--report junit:<path>`, and `--artifacts <dir>` or project equivalents.
- In CI mode, require machine-readable reports and disable viewers or interactive options.
- Let environment variables choose scenario sets only when explicit `--scenario` flags are absent.
- Document ordering constraints for scenarios that mutate device state.

## Preflight Before Device Mutation

Run preflight checks before flashing, OTA, service startup, or other expensive/destructive work:

- exactly one target device is selected, or `--serial` disambiguates it
- hardware identity matches the expected board or SoC
- OS/build/software versions are readable
- target service paths, symlinks, partitions, and params/config stores exist
- host can reach device and device can reach host when streaming or package serving is required
- required host tools exist, such as `adb`, `ffprobe`, `ssh`, or flashing utilities
- free disk/partition space and power/network state are acceptable when relevant

Fail before mutation when preflight fails.

## Scenario Framework

Prefer a small scenario framework over one-off scripts:

- Keep a flat registry of scenario names and builder functions.
- Keep metadata next to the registry: early-exit behavior, reporter needs, viewer needs, reboot/destructive flags, and special tool requirements.
- Make scenario construction side-effect-free. Put resource acquisition in `setup()`, assertions in checks, and cleanup in `teardown()`.
- Always run teardown after setup, including on check failure and interruption.
- Bound teardown and ignore repeated interrupts only long enough to leave the device in a known state.
- Record tracked device params, files, versions, and failure type in the scenario result.
- For scenarios with an abort-on-first-failure policy, report remaining checks as skipped with a clear reason.

## Scenario Ordering

- Run negative/non-reboot scenarios before scenarios that advance firmware or application version.
- Run scenarios that stop shared infrastructure last.
- Make reboot scenarios explicit; capture re-provisioning requirements and expected state after reboot.
- Do not hide stateful ordering in comments only. Enforce it in CLI validation for CI scenario lists.

## Reports And Artifacts

- Write one JUnit testcase per scenario or per meaningful check group.
- Emit operator-readable console output and machine-readable reports.
- Capture bounded device logs on failure, such as the newest N log files.
- Include device versions, scenario names, tracked params, and failure type in artifacts when practical.
- Preserve HIL artifacts with `when: always`.

## Testability Without Hardware

- Put all ADB/SSH/process-manager operations behind adapters that tests can fake.
- Unit-test CLI validation, scenario registry enumeration, reporter output, preflight failure handling, scenario ordering, and teardown behavior without real hardware.
- Keep hardware tests separate from unit/integration tests and mark them clearly in CI.
- For negative OTA or flashing scenarios, share setup helpers rather than duplicating device mutation logic.

## Review Checklist

- Does the design identify the required physical device or runner tag?
- Is access serialized with `resource_group`?
- Is there a non-interactive CI mode with JUnit and artifacts?
- Are preflight checks run before mutation?
- Are cleanup and log capture guaranteed on failure?
- Are destructive scenarios protected/manual where appropriate?
- Are device adapters mockable and covered by tests?
- Is the design blocked explicitly when no device or CI evidence is available?
