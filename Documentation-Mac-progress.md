# Native macOS implementation progress

> Historical progress record from before removal of the Objective-C reference. See Documentation/TESTING.md for current Swift-only validation instructions.


Milestone 1: three package products; shared Foundation presentation types and transition planner;
platform-independent demo contract; native Mac app bundle, hosted tests, UI tests, scheme/test plan,
and canonical build/run command. No renderer is claimed at this scaffold milestone.

Validation: SwiftPM tests with warnings as errors; UIKit demo build (legacy warnings retained);
Mac app build and launch. Logs are retained under ignored artifacts and the test runner logs.

Milestone 2: real NSCollectionView month renderer, reusable day items, localized month/weekday
headings, placeholder policies, bounds, navigation and intrinsic height. Package rendering checks
pass; native hosted/UI results are in artifacts/mac-m2.xcresult. AppKit styling is named
calendarAppearance because NSView.appearance remains the system light/dark appearance property.

Milestone 3: shared renderer assertions, ordered selection transactions, veto/reentry/no-op rules,
configuration pruning, focus, mouse toggling, drag painting, keyboard activation and Tab navigation.
24 package tests, 7 hosted checks and 2 UI checks passed. Actual clicks exposed a document-frame
sizing bug; the native collection subclass now retains the custom layout's full content extent.
Evidence: artifacts/mac-m3-document-fixed.xcresult.

Milestone 4: horizontal/vertical months, horizontal weeks, continuous months with reusable sticky
headers, accumulated scrolling, RTL, backing-scale and live resize geometry. 26 package tests
passed, including 192 navigation operations across four modes with detailed cache <= 9 pages.
Mac hosted and input regression evidence: artifacts/mac-m4.xcresult.

Milestone 5: all 18 native scenarios, shared fixtures/direct launch arguments, custom item registration
and fallback, lunar subtitles/images/events, range example, explicit large fonts and dark appearance.
28 package tests and the full Mac hosted/UI suite passed; the UI matrix selected, reloaded and reset
a date on every scenario and retained screenshots. Evidence: artifacts/mac-m5-flat-accessibility.xcresult.
The collection exposes visible day views directly in accessibility, avoiding AppKit's disabled
intermediate section elements. Native nested-scroll hit testing also has a hosted regression check.

Milestone 6: explicit interactive/settling state, cancellable main-actor animation, source state
until completion, anchoring, replacement/cancellation, resize/configuration handling, external
scope handle, observed Reduce Motion, and native accessibility/focus state. The complete run
passed 33 package tests and 27 Mac Xcode tests; evidence is
artifacts/mac-complete2-20260918T143347Z. Mac clock/memory/launch samples and all 18 screenshots
were exported. A subsequent demo-only dark-window fix is covered by hosted appearance checks
and the passing focused scenario rerun in artifacts/mac-appearance-final-20260918T144327Z
(2 hosted tests plus the 18-scenario UI matrix). See Documentation/MACOS-VALIDATION.md.

Physical iPhone regression after shared-code changes: 106 passing executions, 53 in each
legacy/Swift configuration, iPhone 11 on iOS 17.7.2. Evidence:
artifacts/mac-final-ios-regression-20260918T143708074880Z. The UIKit product also builds with
Swift warnings as errors. macOS 13, iOS 16 runtime, exact Swift 6.2 and human VoiceOver speech
review remain explicitly documented release gates. No vendored Objective-C source was changed.
