# FSCalendar — Swift 6

A Swift 6 rewrite of [FSCalendar](https://github.com/WenchaoD/FSCalendar), originally created by Wenchao Deng and its contributors.

Native UIKit and AppKit calendars with a shared Foundation date engine. Requires Swift 6.2 or later, Swift 6 language mode, and iOS 16+ or macOS 13+. The package contains no SwiftUI, networking, third-party runtime dependency, or Objective-C forwarding.

| SwiftPM product | Contents |
| --- | --- |
| `FSCalendarCore` | Civil dates, page/occurrence identities, Gregorian grids, inclusive bounds, ordered selection transactions |
| `FSCalendar` | Main-actor UIKit view, custom collection layout, reusable cells, appearance, gestures, interactive transitions |
| `FSCalendarAppKit` | Native AppKit view, reusable items, mouse/keyboard focus, all layout modes and cancellable transitions |

## Relationship to the original FSCalendar

This project builds on the ideas and behavior of [WenchaoD/FSCalendar](https://github.com/WenchaoD/FSCalendar), with redesigned Swift APIs and native macOS support.

- **Swift 6:** Swift 6 language mode with main-actor-isolated UI APIs.
- **iOS and macOS:** UIKit and AppKit renderers share the same date engine.
- **Migration:** Existing integrations require API changes. See the [migration guide](Documentation/MIGRATION.md).
- **Behavior contracts:** The Swift rewrite has dedicated core, UIKit, AppKit, and showcase tests. Historical upstream comparisons remain documented in the validation records.

Release versions belong to this rewrite and do not correspond to upstream FSCalendar versions.

## Installation and usage

Add this directory as a local package in Xcode, or add its Git URL after publishing the repository. Link `FSCalendar` and `FSCalendarCore` to your UIKit app. For native Mac apps, link `FSCalendarAppKit` and `FSCalendarCore`; see the [AppKit integration guide](Documentation/APPKIT.md).

```swift
import UIKit
import FSCalendar
import FSCalendarCore

@MainActor
final class CalendarController: UIViewController, FSCalendarDelegate {
    private let calendar = FSCalendar()
    private var height: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        calendar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(calendar)
        height = calendar.heightAnchor.constraint(equalToConstant: calendar.preferredHeight)
        NSLayoutConstraint.activate([
            calendar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            calendar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            calendar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), height
        ])
        calendar.delegate = self
    }

    func calendar(_ calendar: FSCalendar, preferredHeightDidChange value: CGFloat, animated: Bool) {
        height.constant = value
        view.layoutIfNeeded()
    }

    func calendar(_ calendar: FSCalendar, didChangeSelection change: SelectionChange) {
        print(change.selection)
    }
}
```

Mutations validate input and throw `CalendarError`:

```swift
let configuration = try CalendarConfiguration(firstWeekday: 2, selectionMode: .multiple)
try calendar.apply(configuration: configuration)
try calendar.select(CivilDay(year: 2024, month: 2, day: 29))
try calendar.setDisplayMode(.week)
try calendar.navigate(1)
```

Defaults: Gregorian grids, Sunday first, current locale/time zone, horizontal month paging, single selection, six rows, inclusive bounds 1970-01-01...2099-12-31. Both `init(frame:)` and `init(coder:)` are supported; use module `FSCalendar` in storyboards.

## Demo and tests

Open `Example/CalendarShowcase.xcodeproj`, select **CalendarShowcase**, and run Calendar Lab. The showcase runs the Swift implementation. Eighteen scenarios demonstrate paging, continuous sticky headers, selection, placeholders, bounds, custom content/cells, range picking, transitions above a list, sizing, RTL, large text, and dark appearance.

```sh
swift test
./Scripts/test-device.sh YOUR_DEVICE_UDID swift -collect-test-diagnostics never
```

The device script runs the Swift configuration and saves results under ignored `artifacts/`. A successful run leaves the demo installed and opens its scenario list.

See [migration/customization](Documentation/MIGRATION.md), [contracts](Documentation/CONTRACTS.md), [testing](Documentation/TESTING.md), and [current validation results](Documentation/LEGACY-REMOVAL-VALIDATION.md). iOS 16 runtime compatibility remains a separate release check from the iOS 17.7.2 physical-device suite.

## Native Mac demo

Run `./script/build_and_run.sh`, or choose **CalendarShowcaseMac** in the checked-in Xcode project. All 18 scenarios use native AppKit controls and shared fixtures. Run `./Scripts/test-macos.sh --destination 'platform=macOS,arch=arm64'` for package, hosted and UI tests with artifacts and performance measurements. See [Mac validation](Documentation/MACOS-VALIDATION.md) for actual results and pending release gates.

## License and acknowledgments

Distributed under the [MIT License](LICENSE).

Thanks to Wenchao Deng and the contributors to [the original FSCalendar](https://github.com/WenchaoD/FSCalendar) for their work. The original copyright and license notice are preserved.

The former development-only Objective-C reference has been removed; its source and provenance remain available in Git history. See the [dependency audit](Documentation/DEPENDENCIES.md) for current library and development requirements.
