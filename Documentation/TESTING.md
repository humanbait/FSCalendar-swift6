# Testing and device evidence

The checked-in Xcode project has a UIKit app, hosted Swift/Objective-C XCTest bundle, UI-test bundle, shared scheme, and two test-plan configurations: **Legacy baseline** and **Swift rewrite**. Both run core/contracts/characterization/shared hosted tests; their UI matrices choose the respective implementation through `FSCALENDAR_IMPLEMENTATION`.

```sh
swift test
./Scripts/test-device.sh DEVICE_UDID comparison -collect-test-diagnostics never
./Scripts/test-device.sh DEVICE_UDID swift-only -only-test-configuration 'Swift rewrite'
./Scripts/test-device.sh DEVICE_UDID hosted -only-testing:CalendarShowcaseTests
./Scripts/compare-performance.sh DEVICE_UDID
```

The script verifies availability, uses an explicit physical destination and automatic development signing for team MDPX5436J8, then retains device/toolchain/fixture metadata, build output, `.xcresult`, summaries, and attachments under ignored `artifacts/`. On success it launches the installed demo's scenario list. Use your team's signing settings when running on another account.

The runner stops only its own process after 180 seconds without output or 30 minutes total. Override with `FSCALENDAR_TEST_IDLE_TIMEOUT` and `FSCALENDAR_TEST_TOTAL_TIMEOUT` in seconds. XCTest's per-test allowance is 300 seconds. Interrupted/setup-failed runs are retained and never reported as passing. `run.json` records requested UI configurations and actual result configurations.

## Coverage

- Core: leap years, seven first weekdays, month/week boundaries, row counts, DST, skipped civil days, inclusive bounds, date/index/page round trips, invalid/overflow inputs.
- Selection: order, deduplication, atomic replacement, validation, no-op proposals, configuration pruning.
- UIKit contracts: callbacks, veto/reentry, placeholder synchronization, cancellation/replacement/resize, intrinsic height, Dynamic Type, finite geometry, sticky headers/RTL, fractional-height continuous navigation, bounded cache over 120 months.
- Demo: all 18 scenarios and both drivers, selection/reload persistence, custom title/subtitle/image/events after reuse, legacy custom-cell reuse.
- Legacy characterization: exceptions caught in Objective-C, callback behavior, aligned six-row rule, cancelled-pan behavior, calculator normalization.
- UI: tap/reset, paging persistence, repeated scope changes/rotation, custom range cells, swipe selection, continuous scrolling, vertical paging, interactive scope round trip, bounds, five appearance screens, launch measurements, week navigation, dynamic row height, and an iOS 17 accessibility-description audit.

Queries use observable state, occurrence IDs including date and page, and predicate expectations. Rotation waits for controller transition completion. Gesture press durations model gestures; no fixed sleeps synchronize tests.

The UI matrix is one XCTest method with 14 named activities per configuration. This avoids a testmanagerd disconnection between UI methods observed with Xcode 27/iOS 17 while preserving assertions. The test plan retains system and custom screenshots. See `DEVICE-RECOVERY.md` for evidence and recovery history.

Performance tests collect five XCTest clock/memory samples for twelve month navigations and renderer-specific month-screen launches. `compare-performance.sh` runs each renderer's navigation benchmark in a fresh test-host process with the same 390×320 viewport and twelve 2024 month fixtures. Attachments also record continuous-scroll and three scope-round-trip durations including automation overhead. These are observations, not frame-rate claims or hard-coded thresholds. Each run gets `Summary.md` and raw `measurements.json`; regenerate them with `python3 Scripts/summarize_results.py artifacts/RUN`.

## Reproducibility

Launch arguments: `--implementation legacy|swift --scenario SCENARIO`. Names: `month`, `vertical`, `week`, `continuous`, `multiple`, `swipe`, `hidden`, `variable`, `sixRows`, `bounds`, `content`, `custom`, `range`, `scope`, `dynamicHeight`, `rtl`, `largeText`, `dark`.

Fixtures: Gregorian, GMT, en_US_POSIX, initial/today 2024-02-14, bounds 2020-01-01...2030-12-31 (bounds scenario 2024-02-10...2024-03-20). Large Text uses a container content-size override for Swift; legacy retains its explicit large fonts. This does not change the phone's global text-size setting.

## Accessibility and release checks

Automated labels/traits/description audits, RTL, Dynamic Type, and screenshots are distinct from hands-on VoiceOver and Reduce Motion observations. Record manual observations separately. An iOS 17 device pass does not establish iOS 16 runtime or exact Swift 6.2 compiler compatibility.

After adding files, regenerate the checked-in project with `python3 Scripts/generate_project.py`; only Python's standard library is needed. Package consumers do not use the project or any legacy/demo target.
