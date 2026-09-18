# Repository Guidelines

## Project Structure & Module Organization

This Swift package requires Swift 6.2+, Swift 6 language mode, iOS 16+, and macOS 13+.

- `Sources/FSCalendarCore/`: shared Foundation date engine, grids, selection, and transition contracts.
- `Sources/FSCalendar/`: UIKit calendar views, cells, layouts, and gestures.
- `Sources/FSCalendarAppKit/`: native AppKit rendering, input, and transitions.
- `Tests/`: corresponding SwiftPM XCTest suites.
- `Example/`: iOS and Mac showcase apps, Xcode project, hosted tests, and UI tests.
- `Development/`: shared demo fixtures and renderer contract support. Preserve upstream attribution in the root license.
- `Documentation/`: integration, behavior contracts, and validation records. Generated logs, screenshots, and results belong in ignored `artifacts/`.

## Build, Test, and Development Commands

Run commands from the repository root:

- `swift build`: build package targets for the host platform.
- `swift test`: run host-compatible package tests; this does not replace iOS device validation.
- `swift test --filter CalendarEngineTests`: run a focused XCTest suite.
- `./script/build_and_run.sh`: build and launch the native Mac showcase on Apple Silicon.
- `./Scripts/test-macos.sh --destination 'platform=macOS,arch=arm64'`: run package, hosted, and UI tests with retained evidence.
- `./Scripts/test-device.sh DEVICE_UDID swift -collect-test-diagnostics never`: validate the Swift implementation on a physical iOS device. Configure development signing for your account.
- `python3 Scripts/generate_project.py`: regenerate the checked-in Xcode project after adding files; inspect generated changes before committing.

## Coding Style & Naming Conventions

Match existing Swift style: four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Name files after their primary type or responsibility. Keep shared date logic Foundation-only and UI work main-actor isolated. Preserve Swift 6 concurrency checking. No dedicated formatter or linter configuration is checked in.

## Testing Guidelines

Use XCTest with `*Tests.swift` files and descriptive `test...` methods. Add regression coverage for changed behavior, including date boundaries, selection callbacks, reuse, or transitions as applicable. Use deterministic fixtures and predicate expectations instead of fixed sleeps. No numeric coverage threshold is documented; follow `Documentation/TESTING.md` and record platform-specific validation gaps.

## Commit & Pull Request Guidelines

Recent commits use imperative, sentence-case subjects such as “Add shared selection contracts”; follow that pattern. Keep commits focused. PRs should describe the behavior change, link relevant issues, list validation commands and results, and include screenshots for visible UI changes. Preserve unrelated working-tree edits and exclude generated artifacts.
Make sure no uncommited changes before editing.
Commit changes automatically after editing.

## Specific
