# XCTest connection recovery investigation

## Verified recovery

After restarting the iPhone, retaining attachments alone still produced inter-test XCTest disconnections. Grouping the unchanged UI checks into one test with 11 named `XCTContext` activities avoided that boundary. `baseline-matrix-20260914T134312831511Z` passed all 15 tests (14 hosted plus the UI matrix), with zero failures and xcodebuild exit code 0. The date grid also received a unique adapter accessibility identifier to distinguish it from the month-header collection view. No upstream framework implementation was modified.

The investigation below explains the retained settings and earlier failed attempts. Future device runs use the matrix and the same assertions.

## Observed on 2026-09-14

The connected iPhone 11 runs iOS 17.7.2. The host uses Xcode 27.0 (27A266a). Device preparation reports the installed developer disk image as compatible and usable.

After a cable reconnect, the isolated `testBoundsRejectDisabledDay` completed on the iPhone with one passing test, zero failures, and xcodebuild exit code 0. Result finalization took considerably longer than the test itself. The following full-suite run stalled while initiating an XCTest session. Restarting the Mac user's CoreDeviceService did not recover test-session creation. The runner's watchdog recorded this attempt as failed.

The device contains an earlier `testmanagerd-2026-09-14-121744.ips` crash report. Its triggered stack includes:

```
Actor.assertIsolated(_:file:line:)
GlobalActor.preconditionIsolated(_:file:line:)
XCTDHarnessSession._IDE_deleteAttachments(with:)
```

This report predates the current run. It identifies an XCTest attachment-cleanup failure consistent with the observed disconnections, but it does not by itself prove the cause of every stalled session.

## Test-plan change under validation

`Example/CalendarShowcase.xctestplan` retains both UI testing screenshots and custom attachments. This preserves test evidence and aims to avoid the identified cleanup path. The generated `.xctestrun` has been checked: `SystemAttachmentLifetime` and `UserAttachmentLifetime` are both `keepAlways` for the hosted and UI test targets. Assertions, enabled cases, and calendar behavior are unchanged by this setting.

A fresh device connection and complete physical-device run are required to verify this workaround. The Swift rewrite remains behind the agreed baseline gate.

The first retention-enabled retry (`baseline-retained-*`) still stalled before executing any test, despite CoreDevice reporting a fresh tunnel connection. It therefore cannot validate the attachment-cleanup workaround. The phone was unlocked with no authorization prompt. The stalled run was stopped; further device-service recovery is required.

Raw evidence is in ignored `artifacts/baseline-reconnected-20260914T131256174889Z`, `artifacts/baseline-full-*`, and `artifacts/baseline-service-restart-*`. The reconnect run passed; the full runs have not passed.
