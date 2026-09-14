# Testing and device evidence

Open `Example/CalendarShowcase.xcodeproj` and select the shared CalendarShowcase scheme. The development app contains deterministic scenarios and a live state/event readout. The legacy adapter uses real upstream FSCalendar code.

## Physical device

```sh
./Scripts/test-device.sh DEVICE_UDID baseline
```

The script uses an explicit physical-device destination, automatic signing, and the configured development team. It captures device metadata, build output, the result bundle, test summary, and test attachments in `artifacts/`. A successful run leaves Calendar Lab installed and launches its scenario list.

Additional xcodebuild arguments may follow the run label, for example `-only-testing:CalendarShowcaseTests`.

The standard-library Python runner records failed preflight and interrupted runs as well as successes. It stops its own test process after 180 seconds without output or 30 minutes total; override these limits with `FSCALENDAR_TEST_IDLE_TIMEOUT` and `FSCALENDAR_TEST_TOTAL_TIMEOUT` (seconds). Test cases also have XCTest execution limits. Incomplete result bundles remain available for diagnosis; a stopped run is never recorded as passing. `run.json` identifies the fixture configuration, requested device, actual result counts when available, and failure reason.

The shared scheme uses the checked-in `CalendarShowcase.xctestplan`, which retains automatic screenshots and custom attachments on success and failure. See `DEVICE-RECOVERY.md` for the XCTest cleanup issue being investigated on the initial device/toolchain combination. Retention can produce large result bundles; artifacts are ignored by Git.

## Expectations

- Shared behavior tests cover navigation, bounds, selection persistence, and customization.
- Legacy characterization tests record intentionally different upstream behavior.
- Swift contract tests specify the new API and run only against the Swift products.
- UI tests use observable state and XCTest expectations, not fixed sleeps.
- The device UI suite is one test containing 11 named activities. This avoids an inter-test XCTest service crash observed with Xcode 27/iOS 17 while retaining every scenario assertion. Inspect activities inside `testLegacyScenarioMatrix` for individual interactions.
- Performance tests record clock and memory metrics without machine-dependent hard-coded thresholds.

## Accessibility and release checks

Automated labels, traits, screenshots, RTL, and large-text checks do not replace a hands-on VoiceOver and Reduce Motion review. Record these observations separately in the validation report. An iOS 17 device pass does not claim iOS 16 runtime coverage. Minimum-OS validation is a release requirement.

## Project maintenance

The Xcode project is checked in. Regenerate it after adding source files with `python3 Scripts/generate_project.py`; no project-generation dependency is required.
