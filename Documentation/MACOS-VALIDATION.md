# Native Mac validation — 2026-09-18

> Historical validation record: these results predate removal of the vendored Objective-C reference. Legacy comparison commands and counts below describe that earlier checkout. Current instructions are in [TESTING.md](TESTING.md).


## Environment and evidence

Native destination: `platform=macOS,arch=arm64`. Mac mini (Mac16,10), Apple M4,
10 CPU cores, 16 GB RAM; macOS 27.0 (26A428), Xcode 27 (27A266a), Apple Swift 6.4.
The manifest requires Swift 6.2, Swift language mode 6, macOS 13 and iOS 16.

Primary run: `artifacts/mac-complete2-20260918T143347Z/`.
The run records the pre-milestone commit plus the working-tree status and a SHA-256
for every source file, so the tested uncommitted milestone is identifiable. Evidence
includes `run.json`, `package.log`, `build.log`, `Tests.xcresult`, `summary.json`,
`metrics.json` and exported attachments. Artifacts are local and intentionally ignored.
The source milestones are independently committed; see `Documentation-Mac-progress.md`.
After the final demo-only dark-window correction,
`artifacts/mac-appearance-final-20260918T144327Z/` passed all 33 package tests plus
two focused host tests and the complete 18-scenario UI matrix (3 Xcode tests). Its
exported dark screenshot was visually inspected and shows readable controls on the
correct dark window background. No library source changed after the full 27-test run.

## Automated results

- SwiftPM: 33 passing tests (18 core, 15 AppKit), warnings treated as errors.
- Mac window-hosted suite: 22 passing tests, including the same 15 AppKit tests,
  two host checks, two scenario/content checks and three performance tests.
- Mac UI suite: all 5 tests passed, including the 18-scenario matrix. Total Xcode result: 27 passed, zero failures or skips.
- UIKit distributed product: generic physical iOS build passed with Swift compiler
  warnings treated as errors; log retained under `artifacts/mac-final-ios-package/`.
- Physical iPhone regression: **106 test executions passed** (53 in Legacy baseline and
  53 in Swift rewrite), zero failures/skips, on Ling’s iPhone 11 / iOS 17.7.2. Evidence:
  `artifacts/mac-final-ios-regression-20260918T143708074880Z/`. The runner launched the
  installed demo afterward. This supersedes the earlier locked-device attempt.

Assertions cover shared ordered selection, atomic callbacks, veto/reentry, no-op
suppression, configuration pruning, placeholder synchronization and content reload;
all four layouts, RTL geometry, first weekday, bounds, intrinsic height, sticky headers,
focus and item reuse; transition completion/cancellation/replacement, repeated modes,
resize/configuration cancellation and Reduce Motion settlement. The shared Foundation
planner has separate anchor and destination tests. The layout test performs 192
navigation operations across four modes and asserts at most nine detailed page grids.
A release test confirms the view/controller/item ownership graph is reclaimed.

The 18-scenario UI matrix selects a date, reloads, captures an image and resets each
screen. Other UI tests exercise native clicks with Command/Shift, arrow/Space/Tab,
mouse drag painting, trackpad paging, the separate scope handle, ordinary list scrolling,
repeated scope changes and actual window resizing. Predicate expectations synchronize
observable state; gesture durations are input parameters, not test synchronization sleeps.

Superseded failed attempts remain available. They exposed collection document sizing,
AppKit section accessibility wrappers, and incorrect touch-style drag synthesis in Mac
tests. Regression checks now cover those fixes. Superseded compile-only runs are not represented as passing test runs. The earlier
`mac-verified3` UI Tab assertion incorrectly pressed Space on the next control (Reset);
the final suite verifies responder-chain exit in a hosted window and that Tab preserves
selection in UI automation. The first focused appearance rerun passed its hosted tests
but timed out enabling Mac UI automation while the physical iPhone UI suite was active.
A VoiceOver first-use window also remained open during that period. The sequential
rerun passed; the evidence does not isolate either condition as the sole cause.

## Mac performance baseline

Debug configuration, three measured samples per test, same Mac and fixture bounds
2020-01-01 through 2030-12-31, Gregorian/GMT/en_US_POSIX, starting February 2024.
These are elapsed work measurements, not frame-rate or Release-build claims. Each UI
launch sample is a separate application launch. Mac results must not be compared directly
with the previous iPhone baseline.

| Workload | Mean elapsed | Relative standard deviation | Mean process peak physical memory |
| --- | ---: | ---: | ---: |
| 48 month navigations (24 forward, 24 back) | 0.884 s | 2.784% | 178.254 MB |
| 100 continuous scroll offset/layout updates, resetting the starting page | 0.267 s | 2.058% | 181.536 MB |
| 10 interactive month-to-week transitions, 11 progress steps each, immediate settlement and reset | 0.655 s | 1.837% | 178.887 MB |
| Application launch | 0.537 s | 1.123% | — |

Clock and memory raw samples are in `metrics.json` and `build.log`. Memory metrics include
the complete hosted process, demo and XCTest; negative net allocation samples reflect
allocator reclamation and are not evidence of zero allocation or a general leak proof.
Bounded grid-cache and object-release assertions are the separate regression checks.
No historic Mac performance baseline existed before this implementation.

## Accessibility observations

Automated assertions and exposed accessibility state are separate from hands-on results.
The suite checks full civil-date descriptions, selected/disabled state, reusable occurrence
identifiers, RTL, large fonts, dark appearance and Reduce Motion behavior. The collection
exposes visible day controls and continuous month headings rather than disabled section
wrappers; keyboard focus is independent of selection and Tab exits the control.

Hands-on observations (remote native desktop inspection):

- Clicked February 14, moved focus right, and pressed Space: February 15 became selected,
  with the visible focus outline and matching delegate event/readout.
- Large fonts fit the date grid and headings without clipping at the demo's default size.
- Enabled the actual system Reduce Motion switch and completed month/week changes with
  correct page, height and preserved selection. Frame timing was not measured in this
  inspection; instant settlement is separately asserted by the deterministic unit test.
- Toggling VoiceOver in System Settings opened a first-use welcome window. It was later
  located and dismissed with “Turn Off VoiceOver.” Full date labels and selected state
  were exposed to accessibility inspection, but VoiceOver speech and cursor navigation
  were not established. Full VoiceOver operation remains a human release check.
- VoiceOver and Reduce Motion were both verified restored to their original **off** state.
- The dark inspection exposed the demo's light window background behind dark controls;
  the final demo now applies appearance to the window as well as its content. A hosted
  window assertion and a fresh 18-scenario screenshot run cover that correction.

These observations do not replace a human low-vision/VoiceOver usability review or a
numeric contrast audit. The library uses semantic AppKit colors for system contrast
adaptation; custom client colors still require their own checks.

## Remaining release gates

- Execute on an actual macOS 13 runtime; a macOS 13 deployment target on macOS 27 is not
  equivalent to runtime validation.
- Compile with the exact Swift 6.2 toolchain; Swift 6 language mode on Swift 6.4 does not
  establish minimum compiler compatibility.
- Retain the existing iOS 16 runtime gate separately from the iOS 17.7.2 physical-device run.
- A human assistive-technology review remains distinct from automated descriptions and
  the recorded desktop inspection; no universal accessibility conformance is claimed.

Reproduce with `./Scripts/test-macos.sh --destination 'platform=macOS,arch=arm64'`.
Use `./script/build_and_run.sh --verify` to build and leave the native demo open.


## Continuous/week scope animation — 2026-09-29

AppKit now keeps the focused week together across month sections on a reversible
0.3-second ease-in-out timeline. The Mac connected-range container applies each
transition height synchronously and restores its 420-point continuous viewport.
Header/weekday placement, row and separator opacity, and short month titles use the
same progress. Scope requests reverse in place; resize cancellation restores the
original fractional scroll position. Selection, custom bands/dots, keyboard focus,
and the absence of focus outlines remain covered by regression tests.

Validated on Xcode 27.1 / Swift 6.4, macOS 27.0 (26A428), arm64:

| Check | Result | Evidence under ignored `artifacts/` |
| --- | --- | --- |
| `swift test -Xswiftc -warnings-as-errors` | 43 passed | `mac-scope-verified-20260929T090625Z/package.log` |
| Full `test-macos.sh --destination 'platform=macOS,arch=arm64'` | 41 passed (34 hosted, 7 UI) | `mac-scope-verified-20260929T090625Z/` |
| Final hosted frame/capture check with a centered test window | 1 passed; native intermediate capture unavailable | `mac-scope-captures-20260929T091150Z/` |

The final focused run also repeated all 43 SwiftPM tests successfully. Only the test
window's placement and documentation changed after the full pass; renderer and showcase
sources are identical. An earlier regression run exposed fractional scrolling being
lost during resize cancellation; that failure was fixed before the full passing run.

The deterministic checks sample 0%, 25%, 50%, 75% and 100% in both directions,
including February–March and December–January, RTL, fractional dimensions and
scrolling. They inspect live cell frames and alpha values in addition to layout
attributes, require an opaque boundary week, and allow one display pixel at grid
handoffs. Separate tests run real animated collapse/expansion and rapid reversals,
exercise Reduce Motion during settlement, targeted reloads and resize cleanup.
The showcase test verifies that its readout and agenda track each intermediate height.

Native intermediate captures through the hosted test's `screencapture` process were
unavailable even after centering the test window on an attached display: it returned
“could not create image from window”. The test retains that
result as text attachments alongside the JSON geometry trace; these are not screenshot
or visual-animation passes. Native UI window captures remain the visual reference for
connected bands, since AppKit bitmap caching does not reproduce their corner masks.
Inspected the full UI run’s light/dark continuous and scope-round-trip window captures:
the connected February–March band, event dots, separators and 420-point viewport remain
intact, with no rectangular focus outline. These endpoint captures do not substitute for
a visual inspection of intermediate native frames.

No source files were added, so Xcode project regeneration was unnecessary. UIKit and
Core were unchanged. Exact Swift 6.2, macOS 13, and manual VoiceOver remain separate
release checks; the automated Reduce Motion override does not establish a manual
system-preference observation.
