# Swift-only validation — 2026-09-19

The vendored reference, legacy driver/tests, selector, and legacy test configuration have been removed. Public Swift calendar source and package tests are unchanged. All 18 Swift showcase scenarios retain hosted coverage.

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift test -Xswiftc -warnings-as-errors` through the Mac runner | 34 tests passed |
| Native macOS hosted and UI suites | 28 tests passed |
| iPhone 16 Pro simulator, iOS 18.2, hosted and UI suites | 57 tests passed (54 hosted, 3 UI) |
| Physical iPhone 11, iOS 17.7.2 | 52 hosted tests passed; two animation assertions timed out; UI automation initialization timed out |
| Isolated physical-device retry of the two animation tests | Both timeouts reproduced |
| Project regeneration and Python syntax | Passed; generated output reproducible |
| SwiftPM dependency graph | No external dependencies |

The device failures were in the unchanged `testAnimatedScopeCommitAndCancellationPreserveIntermediateGeometry` and `testVariableMonthHeightAnimatesAndRapidReversalEndsAtLatestPage` tests: neither observed an intermediate presentation-layer height within its existing three-second expectation. Both passed on the simulator. This validation does not establish their cause or claim a passing physical-device suite.

Evidence is retained under ignored `artifacts/`:

- `legacy-removal-20260918T175212Z/`: package and macOS run, metadata, result bundle, screenshots.
- `LegacyRemovalSimulator.xcresult`: complete simulator test results and screenshots.
- `legacy-removal-20260918T175316212122Z/`: physical-device failure evidence.
- `legacy-removal-animation-recheck-*/`: isolated device retry evidence.
- `legacy-removal-showcase.png`: Swift-only scenario list without an implementation selector.

The final UIKit and AppKit app builds also pass after removal of the obsolete Objective-C linker flag. Minimum iOS/macOS runtime, exact Swift 6.2, and manual accessibility release checks remain separate from this validation. See [dependencies](DEPENDENCIES.md) and [testing instructions](TESTING.md).
