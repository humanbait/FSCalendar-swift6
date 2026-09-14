# Validation — 2026-09-14

The implemented Swift package and real Objective-C reference pass the automated physical-device suite. Manual accessibility and minimum-runtime checks below remain release gates; this report does not claim release certification.

## Device and toolchain

- Ling's iPhone: iPhone 11, iOS 17.7.2 (21H221), USB, UDID `00008030-000948522284802E`.
- Xcode 27.0 (27A266a), Swift 6.4, Swift 6 language mode; package minimum tools version 6.2.
- App/library deployment target iOS 16.0. Automatic development signing, team MDPX5436J8.
- Fixed Gregorian/GMT/en_US_POSIX fixtures and dates described in `TESTING.md` and each run's `run.json`.

## Tests-first baseline

`artifacts/baseline-matrix-20260914T134312831511Z` passed **15 tests**, zero failed/skipped, xcodebuild exit 0, on the physical iPhone before substantive Swift implementation began. This included 14 hosted Swift/Objective-C tests and the real legacy UI matrix with 11 named groups. Local commit `bc6d631` preserves that baseline.

No mock calendar substituted for the reference. All 32 original vendored source hashes match the upstream snapshot; only a development umbrella header was added. Earlier device-service failures and the verified matrix workaround are documented in `DEVICE-RECOVERY.md`. Legacy expectations have been retained, including exceptions, callback behavior, and the aligned-month extra leading week.

The core tests were written before the corresponding engine. The initial missing-type failure is retained in `artifacts/package-verification/initial-red-tests.log`.

## Final automated results

`artifacts/final-verified-20260914T144155586310Z`:

| Test-plan configuration | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Legacy baseline | 50 | 0 | 0 |
| Swift rewrite | 50 | 0 | 0 |

This is **100 executions of 50 distinct XCTest methods**. xcresulttool's top-level summary deduplicates methods across configurations. Each configuration includes 49 hosted tests (16 core, 15 UIKit contracts, 14 legacy tests, 4 shared-driver tests) and one UI matrix with 14 named activities. The script completed with exit 0 and launched the installed scenario list.

All 18 scenarios instantiate and expose fixture state through both drivers. UI checks cover tapping/reset, paging in both axes, week paging, bounds, single/multiple/swipe/range selection, custom cells, continuous scrolling, repeated scope changes, interactive transitions, rotation, dynamic row height, RTL, large text, dark appearance, and accessibility descriptions. Hosted contracts additionally verify cancellation/replacement/resize, typed errors, atomic callbacks/veto/reentry, content reuse, placeholder synchronization, sticky geometry, all first weekdays, DST/skipped civil days, and bounded detailed cache growth over 120 month changes.

`Summary.md`, `measurements.json`, `run.json`, `summary.json`, `Tests.xcresult`, build logs, and exported screenshots are retained in that artifact directory. Failed development runs remain available as history; their results are not counted as final passes.

The independent SwiftPM `FSCalendar` iOS build passed with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. Both products compile in Swift 6 with no Swift concurrency warnings. `swift test` separately passed all 16 Foundation tests on the Mac. Logs and final source hashes are in `artifacts/package-verification/`. Xcode's development test project emits non-concurrency notices about App Intents metadata and XCTest libraries built for iOS 17; these are not distributed package dependencies.

## Same-device performance observations

Navigation benchmarks use five measured iterations, each visiting all twelve 2024 months synchronously with a 390×320 calendar viewport. Separate fresh test-host processes avoid allocations from earlier demo scenarios contaminating the comparison:

- Legacy: `artifacts/performance-legacy-20260914T144751344562Z`, 1 test passed, exit 0.
- Swift: `artifacts/performance-swift-20260914T144756805406Z`, 1 test passed, exit 0.

| Measurement | Legacy | Swift |
| --- | ---: | ---: |
| Twelve month layouts, mean | 0.1101 s | 0.1032 s |
| Test-host peak physical memory, mean | 19.29 MB | 28.81 MB |
| Month-scenario launch, mean of five samples | 0.2859 s | 0.3655 s |
| Continuous swipe and settle, one UI sample | 3.984 s | 4.146 s |
| Three month/week round trips, one UI sample | 12.393 s | 12.458 s |

Launch and interaction samples come from the full final comparison. UI interaction times include XCTest injection, idling, and predicate overhead; they are not animation/frame timings. Navigation variance was about 0.45% for legacy and 11.54% for Swift, so these samples do not establish a reliable navigation speed advantage. Swift used approximately 9.5 MB more peak test-host memory and launched the month screen about 80 ms slower in this run. These are observed costs to optimize, not hidden parity claims. Memory measures the whole host, including frameworks and system caches. The last Swift navigation iterations plateaued rather than showing continued positive growth; the nine-page cache limit is also asserted directly. This is not a substitute for a long-duration leak profile.

The original baseline launch test opened the scenario list; the final launch comparison explicitly opens the month renderer for both implementations. Those two launch measurements should not be compared directly. Reproduce isolated navigation with `Scripts/compare-performance.sh DEVICE_UDID`.

## Accessibility observations

**Automated:** Both physical-device UI configurations passed Apple's iOS 17 sufficient-element-description audit. UIKit tests confirm full weekday labels, Dynamic Type trait propagation up to accessibility XXXL, larger preferred height, event descriptions, and occurrence identity. Screenshot scenarios cover a container accessibility-medium text setting, RTL, and light/dark content.

**Visual review of device screenshots:** The final RTL weekday headings align with the mirrored dates. Large-text dates and status labels remain readable with the scrolling demo container. Custom titles, lunar subtitles, heart images, and event dots render without the earlier image/subtitle overlap. This was screenshot inspection, not a spoken-output review.

**VoiceOver attempt:** CoreDevice reported VoiceOver enabled, but iOS displayed its first-use gesture confirmation alert. The content screen was visible behind the alert. VoiceOver was restored to its original disabled setting and that state was verified. The user dismissed the remaining alert on the phone; a successful VoiceOver focus/announcement/activation walkthrough is not claimed. The attempted Device Hub control path timed out. Screenshot evidence is retained under `artifacts/accessibility-review/`.

**Manual checks still required:** Use VoiceOver to navigate, hear full dates/selection/event announcements, select/deselect, and page. Enable Reduce Motion in Settings and inspect transitions, cancellation, and repeated mode changes, then restore the original setting. The implementation consults the system Reduce Motion setting, but an actual enabled-setting walkthrough has not been completed. Description audits do not establish contrast, hit-area, or every accessibility requirement.

## Remaining release requirements

1. Complete and record the hands-on VoiceOver and Reduce Motion checks above.
2. Run on iOS 16. Installed runtimes start at iOS 18.2; the connected iOS 17.7.2 device does not establish iOS 16 runtime compatibility. The library's iOS 16 deployment build passes.
3. Validate with the exact minimum Swift 6.2 compiler before publishing a release. Current successful builds used Swift 6.4 in Swift 6 mode.

There are no unexplained failing shared-behavior assertions in the final device result. Deliberate differences are documented in `CONTRACTS.md` and `MIGRATION.md`.
