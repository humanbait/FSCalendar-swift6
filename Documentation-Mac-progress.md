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

Milestone 3: shared renderer assertions, ordered selection transactions, veto/reentry/no-op rules,
configuration pruning, focus, mouse toggling, drag painting, keyboard activation and Tab navigation.
24 package tests, 7 hosted checks and 2 UI checks passed. Actual clicks exposed a document-frame
sizing bug; the native collection subclass now retains the custom layout's full content extent.
Evidence: artifacts/mac-m3-document-fixed.xcresult.
