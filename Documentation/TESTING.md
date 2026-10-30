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

## Connected-range height and macOS focus outlines — 2026-09-29

Connected bands now reuse the inherited today-circle diameter on both renderers,
centered in the cell while retaining their horizontal joins and rounded ends.
AppKit no longer draws a rectangular focus outline; focus tracking, accessibility,
keyboard navigation and selection remain active.

Validated with Xcode 27.1 / Swift 6.4, macOS 27.0 arm64, and iPhone 11 / iOS 17.7.2:

| Check | Result | Local evidence under `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 40 passed | `range-height-final-20260929T081523Z/package.log` |
| Full macOS validation runner | 36 passed; one scenario-reset assertion failed | `range-height-20260929T080811Z/` |
| Isolated scenario-reset rerun, unchanged test | 1 passed | `range-height-reset-rerun-20260929T081300Z/` |
| Final Mac example tests and light/dark connected-range UI tests | 7 passed | `range-height-final-20260929T081523Z/` |
| Physical-iPhone example tests and connected-range UI test | 10 passed | `range-height-20260929T080826332741Z/` |

Height assertions compare against the standard today circle at three cell sizes,
including fractional and wide cells, selected/unselected states, event/no-event content,
short month labels, RTL and repeated layout. Existing coverage verifies connected joins,
February 29–March 1, targeted reloads, reuse and continuous/week round trips. AppKit tests
assert zero cell border width after mouse-path activation and arrow navigation while
accessibility focus and selection still update; the desktop UI suite also checks Space,
Tab, dragging, scrolling and window resizing.

The scenario-reset failure did not reproduce in isolation; no reset code or assertion
was changed. The final UI captures use `FSCALENDAR_TEST_APPEARANCE` in the showcase
process because the initial `AppleInterfaceStyle` launch preference did not actually
change the appearance. Inspected native light/dark window captures show the today circle
beside equal-height selected bands with no focus outline. iPhone light/dark captures also
retain event dots and month separators. Evidence remains in ignored `artifacts/`.
No source files were added, so project regeneration was unnecessary. Exact Swift 6.2,
iOS 16, macOS 13 and manual VoiceOver remain untested release gates.

## Smooth UIKit continuous/week scope animation — 2026-09-29

Continuous-month/week switching now keeps the anchor week visible on one 0.3-second
UIKit animator, including rows owned by two adjacent month sections. Height starts
from the actual viewport; expanding restores the remembered continuous height. Header,
weekday placement, other rows, separators and first-day labels share that timeline.
Repeated destinations do not restart it, and opposite requests reverse it in place.
The connected-range driver forwards transition heights and suppresses duplicate final
height updates. AppKit and public APIs are unchanged.

Validated on Xcode 27.1 / Swift 6.4 and the physical iPhone 11 running iOS 17.7.2:

| Check | Result | Local evidence under `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 40 passed | `smooth-scope-final-20260929T083936687554Z/package.log` |
| Full iPhone hosted suite and connected-range UI test | 68 passed (67 hosted + 1 UI) | `smooth-scope-final-20260929T083936687554Z/` |

Tests sample the actual presentation layers at 0, 25, 50, 75 and 100 percent in both
directions and both appearances. They assert synchronized viewport/header motion,
opaque boundary-week cells, fading surrounding rows, no header/weekday overlap, and
no preparation or completion height jump beyond one display pixel. Retained window
captures and JSON frame traces accompany these checks. Additional regressions cover
fractional scrolling, February 29–March 1, selected bands and dots, short month labels,
RTL, Dynamic Type row sizing, resize cancellation, rapid reversal, Reduce Motion and
transition cleanup. Existing paged-month/week animation tests also pass.

Intermediate frame inspection exposed header overlap and late-created rows missing
the fade; both were corrected before the final run. Inspected the final light/dark
frame sequences for coordinated motion and preserved cell styling. The iPhone UI test
also exercises ordinary button-driven scope round trips. No source files were added,
so project regeneration was unnecessary. macOS UI validation was not repeated because
its renderer and demo were unchanged. Exact Swift 6.2, iOS 16 and manual VoiceOver
remain untested release gates; evidence stays under ignored `artifacts/`.


## Smooth AppKit continuous/week scope animation — 2026-09-29

AppKit now coordinates focused-week movement, viewport height, heading/weekday layout,
row and separator fades, and short month titles on one reversible 0.3-second timeline.
The connected-range showcase returns to 420 points and positions its readout and agenda
from every intermediate height. Repeated destinations are ignored, opposite requests
reverse in place, and resize cancellation restores fractional scrolling.

See [Mac validation](MACOS-VALIDATION.md#continuousweek-scope-animation--2026-09-29)
for the quarter-step geometry checks, real animation/reversal coverage, native capture
evidence and platform limitations. Existing paged transitions remain covered.

## UIKit weekday spacing — 2026-10-31

The UIKit default weekday band and nonfinite-value fallback are now 18 points.
The existing font-line-height minimum remains in force for Dynamic Type.

Validation command:

```sh
./Scripts/test-device.sh 00008030-000948522284802E weekday-spacing -collect-test-diagnostics never -only-testing:CalendarShowcaseTests/CalendarViewTests -only-testing:CalendarShowcaseUITests/CalendarShowcaseUITests/testSharedScenarioMatrix
```

All 39 UIKit contract tests passed on iPhone 11 / iOS 17.7.2, including default,
custom and invalid weekday heights, large text, grid alignment, and existing
transition coverage. The UI matrix failed before exercising screens with
`Lost connection to testmanagerd`; the overall device run is therefore failed.
Evidence is retained in `artifacts/weekday-spacing-20261030T164749712371Z/`.

As a visual fallback, the showcase built and ran on iPhone 16 / iOS 18.2 Simulator.
Month, week, continuous months, and large text were inspected with readable weekday
labels and no weekday/day overlap. Screenshots are retained in
`artifacts/weekday-spacing-simulator/{month,week,continuous,largeText}.png`.
This visual check does not replace the incomplete physical-device UI matrix.

## Rounded month boundaries and alternating fills — 2026-10-31

Continuous-month calendars on UIKit and AppKit now use 8-point rounded separator
bends and alternating neutral month backgrounds. Both are customizable through
`monthSeparatorCornerRadius` and `alternatingMonthBackgroundColor`. Fills share the
separator geometry and animate with the existing scope transition.

Validated with Xcode 27.2 (27B48), Swift 6.4.2 in Swift 6 mode, macOS 27.0.1 arm64,
a physical iPhone 11 on iOS 17.7.2, and an iPhone 16 simulator on iOS 18.2:

| Check | Result | Evidence under ignored `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 45 passed | `rounded-months/package.log` |
| Full `test-macos.sh --destination 'platform=macOS,arch=arm64'` | 43 hosted/UI tests passed, plus 45 package tests | `rounded-months-20261030T172913Z/` |
| Physical iPhone hosted suite | 71 passed; subsequent UI runner disconnected | `rounded-months-ios-20261030T172914783282Z/` |
| Isolated physical iPhone connected-range UI retry | Failed before UI actions: `Lost connection to testmanagerd` | `rounded-months-ios-ui-20261030T173123966776Z/` |
| iOS 18.2 simulator connected-range UI flow | Passed, including light and dark activities | `rounded-months/SimulatorTests.xcresult` |

The two physical-device runs remain failed runs; hosted success does not establish a
physical-device UI pass. Simulator validation covers the UI flow without changing or
relaxing its assertions. The showcase's `FSCALENDAR_TEST_APPEARANCE` environment setting
now supports UIKit as well as AppKit, allowing theme-specific UI captures without
changing the device's global appearance.

Regression assertions cover all seven first weekdays, fractional dimensions, 1x/2x/3x
stroke alignment, rounded and square paths, radius normalization, RTL, December–January
color parity, changed range starts, fill ownership without gaps or overlap, empty outer
slots, customization and opt-out, decoration copying/reuse, input/accessibility isolation,
and continuous/week opacity and reversal cleanup. Existing selection, events, keyboard,
scrolling, resizing, Reduce Motion, and transition suites pass.

Inspected native Mac UI and simulator light/dark screenshots show February–April both
unselected and selected across February 29–March 1. Physical iPhone hosted captures also
verify light/dark rendering and connected bands. Descriptive copies are in
`rounded-months/{appkit,swift}-rounded-months-{unselected,selected}-{light,dark}.png`.
The project was regenerated for the new UIKit geometry source; unrelated generated
scheme formatting was discarded. Exact Swift 6.2, iOS 16, macOS 13, manual VoiceOver,
and a successful physical-device UI run remain separate validation gaps.
