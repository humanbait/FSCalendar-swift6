# Testing and device evidence

The checked-in Xcode project has a UIKit app, hosted Swift XCTest bundle, UI-test bundle, shared scheme, and one test-plan configuration: **Swift rewrite**. It runs core, UIKit contract, Swift driver, and UI tests. The showcase always uses Swift.

```sh
swift test
./Scripts/test-device.sh DEVICE_UDID swift -collect-test-diagnostics never
./Scripts/test-device.sh DEVICE_UDID swift-only -only-test-configuration 'Swift rewrite'
./Scripts/test-device.sh DEVICE_UDID hosted -only-testing:CalendarShowcaseTests
./Scripts/test-performance.sh DEVICE_UDID
```

The script verifies availability, uses an explicit physical destination and automatic development signing for team MDPX5436J8, then retains device/toolchain/fixture metadata, build output, `.xcresult`, summaries, and attachments under ignored `artifacts/`. On success it launches the installed demo's scenario list. Use your team's signing settings when running on another account.

The runner stops only its own process after 180 seconds without output or 30 minutes total. Override with `FSCALENDAR_TEST_IDLE_TIMEOUT` and `FSCALENDAR_TEST_TOTAL_TIMEOUT` in seconds. XCTest's per-test allowance is 300 seconds. Interrupted/setup-failed runs are retained and never reported as passing. `run.json` records requested UI configurations and actual result configurations.

## Coverage

- Core: leap years, seven first weekdays, month/week boundaries, row counts, DST, skipped civil days, inclusive bounds, date/index/page round trips, invalid/overflow inputs.
- Selection: order, deduplication, atomic replacement, validation, no-op proposals, configuration pruning.
- UIKit contracts: callbacks, veto/reentry, placeholder synchronization, cancellation/replacement/resize, intrinsic height, Dynamic Type, finite geometry, continuous heading removal/restoration, localized month labels, stepped separators/shared boundary weeks/RTL, fractional-height continuous navigation, bounded cache over 120 months.
- Demo: all 19 Swift scenarios, selection/reload persistence, custom title/subtitle/image/events after reuse.
- UI: tap/reset, paging persistence, repeated scope changes/rotation, custom range cells, a dedicated combined-usage connected range with continuous month scrolling and button-only scope changes, swipe selection, continuous scrolling, vertical paging, interactive scope round trip, bounds, five appearance screens, launch measurements, week navigation, dynamic row height, and an iOS 17 accessibility-description audit.

Queries use observable state, occurrence IDs including date and page, and predicate expectations. Rotation waits for controller transition completion. Gesture press durations model gestures; no fixed sleeps synchronize tests.

The UI matrix is one XCTest method with 14 named activities per configuration. This avoids a testmanagerd disconnection between UI methods observed with Xcode 27/iOS 17 while preserving assertions. The test plan retains system and custom screenshots. See `DEVICE-RECOVERY.md` for evidence and recovery history.

Performance tests collect five XCTest clock/memory samples for twelve month navigations and Swift month-screen launches. `test-performance.sh` runs the Swift navigation benchmark in a fresh test-host process with the same 390×320 viewport and twelve 2024 month fixtures. Attachments also record continuous-scroll and three scope-round-trip durations including automation overhead. These are observations, not frame-rate claims or hard-coded thresholds. Each run gets `Summary.md` and raw `measurements.json`; regenerate them with `python3 Scripts/summarize_results.py artifacts/RUN`.

## Reproducibility

Launch arguments: `--scenario SCENARIO`. Names: `month`, `vertical`, `week`, `continuous`, `multiple`, `swipe`, `hidden`, `variable`, `sixRows`, `bounds`, `content`, `custom`, `range`, `connectedRange`, `scope`, `dynamicHeight`, `rtl`, `largeText`, `dark`. The showcase lists `connectedRange` separately under **Combined usage**. It opens in vertically scrolling continuous months; only the Scope button switches to week scope and back. Tap two days to select an inclusive band; later taps outside extend it, while taps inside leave it unchanged. Connected-range titles are centered in their cells. Days 1, 5, 9, 14, 18, 22, and 29 have one sample event dot below the title, using the event color normally and the selected-title color inside a band; accessibility values include “Has events”.

Fixtures: Gregorian, GMT, en_US_POSIX, initial/today 2024-02-14, bounds 2020-01-01...2030-12-31 (bounds scenario 2024-02-10...2024-03-20). Large Text uses a container content-size override. This does not change the phone's global text-size setting.

## Accessibility and release checks

Automated labels/traits/description audits, RTL, Dynamic Type, and screenshots are distinct from hands-on VoiceOver and Reduce Motion observations. Record manual observations separately. An iOS 17 device pass does not establish iOS 16 runtime or exact Swift 6.2 compiler compatibility.

After adding files, regenerate the checked-in project with `python3 Scripts/generate_project.py`; only Python's standard library is needed. Package consumers do not use the project or any demo target.

## Native macOS

The independent `CalendarShowcaseMac` scheme and test plan run AppKit window-hosted tests,
shared renderer contracts, all 19 scenario UI checks, desktop input and transition checks,
and Mac-specific clock, memory and launch measurements.

```sh
./Scripts/test-macos.sh --destination 'platform=macOS,arch=arm64'
./Scripts/test-macos.sh --destination 'platform=macOS,arch=arm64' --label input -- -only-testing:CalendarShowcaseMacUITests/MacUITests/testMouseToggleAndKeyboardFocus
```

The runner first executes SwiftPM tests with warnings as errors, then Xcode tests against
the explicit Mac destination. Every run records source hashes (including uncommitted files),
Git revision/status, hardware, OS, compiler, fixtures, logs, `.xcresult`, exported screenshots
and metrics. Passing runs reopen the Mac demo. See [AppKit integration](APPKIT.md) and
[Mac validation](MACOS-VALIDATION.md) for evidence and remaining runtime release gates.

## Continuous-month validation — 2026-09-24

Validated with Xcode 27.1 (27A9269), Swift 6.4 in Swift 6 language mode,
macOS 27.0 (26A428, arm64), and a physical iPhone 11 running iOS 17.7.2 (21H221).

| Check | Result | Local evidence under `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 38 passed | `continuous-20260924T052756Z/package.log` |
| Full `test-macos.sh --destination 'platform=macOS,arch=arm64'` | 33 hosted/UI tests passed | `continuous-20260924T052756Z/` |
| Physical iOS hosted suite plus connected-range UI test | 61 passed | `continuous-final-20260924T053629302552Z/` |
| Physical iOS swipe-height UI test, isolated | 1 passed | `swipe-final-20260924T053801056184Z/` |
| Physical iOS main scenario matrix and animation-parity UI test | Both passed in the initial mixed-result run | `continuous-20260924T052812853939Z/` |

All 64 distinct iOS tests passed across these runs; the initial full run itself failed.
It exposed two animation-test synchronization failures and lost the `testmanagerd`
connection while launching two standalone UI tests. Animation checks now wait for a
presented starting frame, observe intermediate frames using the existing frame timer,
and allow one display pixel when comparing rendered endpoints. They pass in isolation
and in the final full hosted suite. Both interrupted UI cases passed in fresh sessions;
no library behavior or assertions were disabled to recover them.

New coverage checks unique owned-month dates, shared rows for all seven first weekdays
and all placeholder modes, leap/year boundaries, skipped civil days, selection bounds,
RTL, fractional row heights, final-month alignment, heading updates, targeted reloads,
AppKit focus across month boundaries, scope round trips, and bounded caches. Window-hosted
and UI tests verify a connected February 29–March 1 band. Exported
`appkit-connected-range-continuous` and `swift-connected-range-continuous` screenshots
were visually checked: each shows those dates beside one another with no repeated week.

Library and Mac test sources were unchanged after the full Mac pass. Subsequent edits
only stabilized UIKit animation checks, extended UIKit cache coverage, and recorded this
evidence. Exact Swift 6.2, iOS 16, macOS 13, and manual VoiceOver validation remain separate
gates; these runs do not establish those configurations.

## Month separators and short labels — 2026-09-24

Validated on the same Xcode 27.1 / Swift 6.4 toolchain, macOS 27.0 arm64, and
physical iPhone 11 with iOS 17.7.2. Continuous mode now hides the heading and its
height, uses localized short month names on first days, and draws stepped rules.

| Check | Result | Local evidence under `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 40 passed | `month-separators-final-20260924T060312Z/package.log` |
| Full `test-macos.sh --destination 'platform=macOS,arch=arm64'` | 35 hosted/UI tests passed | `month-separators-final-20260924T060312Z/` |
| Physical iPhone hosted suite and `testConnectedRangeCombinedUsage` | 63 passed | `month-separators-final-20260924T060309645114Z/` |

Regression coverage includes all seven first weekdays, mixed and aligned boundaries,
December–January and leap-day boundaries, RTL, fractional dimensions, pixel alignment,
visible decoration queries, decoration copying/color changes, and noninteractive rules.
Date-cell assertions exclude decoration attributes. Label tests cover English, German,
Russian, and Chinese; custom titles (including empty titles), subtitles/images, reuse,
targeted reloads, and unchanged full-date accessibility. Heading removal/restoration,
selection, resizing, navigation, bounded caches, keyboard focus, and continuous/week
round trips also pass.

Exported `swift-month-separators-light/dark` and `appkit-month-separators-light/dark`
attachments were inspected for short month labels and separator geometry/color. The
connected-range UI captures and hosted geometry assertions verify the band across
February 29–March 1; AppKit's bitmap view captures do not reproduce selective layer
corner masks, so the live UI capture is the visual reference for its connected band.
Screenshots, logs, result bundles, and manifests remain in ignored `artifacts/`.

The first macOS Xcode run reused stale generated Core module data and failed to find
an existing continuous-grid API. Cleaning `artifacts/MacDerivedData` with `xcodebuild clean`
resolved it; the full rerun passed without changing the Core model. The generated project
diff adds the UIKit decoration source; AppKit discovers its source through SwiftPM.
Exact Swift 6.2, iOS 16, macOS 13, and manual VoiceOver remain untested release gates.

## Centered connected-range titles and event dots — 2026-09-29

The UIKit and AppKit connected-range examples center both numeric and short-month
titles in the full cell. A private four-point layer displays one dot three points below
the title on the shared sample event dates. Selected dots use the selected-title color;
normal dots honor the event color. Standard cells and library APIs are unchanged.

Validated with Xcode 27.1, Swift 6.4, macOS 27.0 arm64, and the physical iPhone 11:

| Check | Result | Local evidence under `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 40 passed | `connected-events-verified-20260929T075332Z/package.log` |
| Full macOS validation runner | 36 hosted/UI tests passed | `connected-events-final-20260929T074837Z/` |
| Final Mac example tests and connected-range UI test | 6 passed | `connected-events-verified-20260929T075332Z/` |
| Final physical-iPhone example tests and connected-range UI test | 10 passed | `connected-events-complete-20260929T075329705602Z/` |

The full Mac pass preceded the final explicit dot layer ordering; the focused rerun
covers that final implementation. Assertions check title/circle centers, fractional
sizes, RTL, single-dot counts and spacing, selected/custom/theme colors, inherited-dot
suppression, reuse, targeted reloads, accessibility values, February–March boundaries,
and continuous/week round trips. An initial UIKit scope assertion inspected retained
reusable subviews; it now reads visible cells and waits for their expected configuration.
The final run passes without relaxing the title or event assertions.

Light/dark `swift-connected-events-*` and `appkit-connected-events-*` captures were
inspected. AppKit bitmap caching does not faithfully composite custom sublayers over
native subviews or selective corner masks; the window-only
`appkit-connected-range-continuous` UI capture verifies visible white dots and connected
bands. Evidence stays in ignored `artifacts/`. Exact Swift 6.2, iOS 16, macOS 13, and
manual VoiceOver checks remain untested release gates. No new source files were added,
so project regeneration was unnecessary.
