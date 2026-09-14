# Validation status

## Environment

- Physical device: iPhone 11, iOS 17.7.2 (21H221), connected by USB.
- Host toolchain: Xcode 27.0 (27A266a), Swift 6.4; demo and tests compile in Swift 6 language mode.
- Deployment target: iOS 16.0. No iOS 16 runtime validation has been performed.
- Signing: automatic development signing, team MDPX5436J8, using an existing valid development certificate.

## Baseline results — 2026-09-14

**Baseline gate passed:** `baseline-matrix-20260914T134312831511Z` completed on the physical iPhone with xcodebuild exit code 0: 15 tests passed, zero failures, zero skipped. This consists of 14 hosted unit/characterization tests and one UI matrix containing all 11 named scenario groups. The script successfully launched the installed demo's scenario list after testing.

The UI matrix covers tap/reset, paging/selection persistence, scope changes/rotation, range/custom cells, swipe selection, continuous scrolling, vertical paging, interactive scope transitions, bounds, appearance scenarios, and launch performance. Test assertions were preserved when grouping the original UI methods into activities to avoid the inter-test XCTest disconnection. The vertical paging test was corrected to target the date grid rather than the separate month-header collection view.

The earlier attempts below are retained as investigation history, not the final baseline result.

- All 11 hosted unit/characterization tests passed on the physical device in the expanded baseline run.
- All 18 demo scenarios were instantiated, laid out, and reloaded by the hosted tests.
- Appearance UI scenarios (content, RTL, large text, dark appearance, dynamic height) passed and captured screenshots.
- Continuous scrolling UI interaction passed. A subsequent fixture improvement explicitly resets its initial page after the view appears; its strengthened assertion still needs a completed device rerun.
- Remaining UI cases have not completed successfully: XCTest lost its device-service connection between cases, and isolated retries stalled during test-session initialization.
- The initial iOS “Enable UI Automation” authorization prompt was resolved before the successful UI cases.
- After a USB reconnect, the isolated bounds UI test completed with one pass, zero failures, and xcodebuild exit code 0 (`baseline-reconnected-20260914T131256174889Z`). Subsequent full runs still stalled during XCTest session initialization.
- Three additional hosted tests now compile: placeholder selection synchronization, custom content after cell reuse, and custom-cell class reuse across 12 months. Their device execution remains pending; the confirmed hosted pass count is still 11.
- The checked-in test plan now retains all system and custom attachments. The generated test configuration has been verified; the recovery hypothesis and pending verification are described in `DEVICE-RECOVERY.md`.

The initial calculator round-trip failure was a test setup error: the test queried the internal calculator before requesting normalized date bounds after a time-zone change. Calling the framework's `reloadData()` first fixed all 21 failing assertions. No vendored implementation source was changed.

Legacy cancellation is explicitly characterized: a cancelled scope pan can commit the target scope. The new Swift contract will restore the source state instead.

## Evidence

Raw results are stored in the ignored `artifacts/` directory:

- `baseline-unit-20260914T124734Z`: completed 10-test unit run, exit status 0.
- `baseline-20260914T124958Z`: expanded run with 11 passing hosted tests and successful initial UI cases, interrupted after device-service disconnections.
- `baseline-bounds-*`: isolated device-test recovery attempts.

Performance measurements were collected on-device for 12 consecutive month layouts, using XCTest clock and memory metrics. They are baseline observations, not a completed comparison against Swift.

## Outstanding gates

1. Implement the Swift engine and renderer, preserving the agreed tests-first ordering.
2. Validate shared scenarios and new contracts against Swift on the same device.
3. Complete hands-on VoiceOver/Reduce Motion review and iOS 16 runtime validation before release.

The legacy baseline has passed. A completed Swift rewrite and release readiness are not yet claimed.
