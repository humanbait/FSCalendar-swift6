# Native macOS implementation progress

Milestone 1: three package products; shared Foundation presentation types and transition planner;
platform-independent demo contract; native Mac app bundle, hosted tests, UI tests, scheme/test plan,
and canonical build/run command. No renderer is claimed at this scaffold milestone.

Validation: SwiftPM tests with warnings as errors; UIKit demo build (legacy warnings retained);
Mac app build and launch. Logs are retained under ignored artifacts and the test runner logs.

Milestone 2: real NSCollectionView month renderer, reusable day items, localized month/weekday
headings, placeholder policies, bounds, navigation and intrinsic height. Package rendering checks
pass; native hosted/UI results are in artifacts/mac-m2.xcresult. AppKit styling is named
calendarAppearance because NSView.appearance remains the system light/dark appearance property.
