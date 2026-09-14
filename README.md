# FSCalendar Swift 6

A UIKit calendar rewrite targeting iOS 16+, built with Swift 6 language mode and SwiftPM distribution.

## Current milestone

The development project contains a real Objective-C reference calendar, 18 deterministic UIKit scenarios, hosted unit tests, legacy characterization tests, and XCUITests. The Swift engine and renderer will be implemented after the full baseline passes on the connected physical device.

Open `Example/CalendarShowcase.xcodeproj` and run **CalendarShowcase** to explore the demo. To reproduce device validation:

```sh
./Scripts/test-device.sh YOUR_DEVICE_UDID baseline
```

The device may request its passcode to enable XCTest UI Automation. Enter it directly on the device. Detailed results are saved under `artifacts/` and excluded from Git.

See [testing](Documentation/TESTING.md) and [legacy provenance](Development/Legacy/README.md). The upstream Objective-C checkout is unchanged.

## Intended package products

- **FSCalendarCore:** Foundation-only date arithmetic, immutable day/page models, and selection rules.
- **FSCalendar:** Main-actor UIKit view, custom collection-view layout, cells, styling, and interactive transitions.

The development-only legacy implementation and demo adapters will not be distributed as part of these products.

## License

MIT; see [LICENSE](LICENSE). Original FSCalendar attribution is retained.
