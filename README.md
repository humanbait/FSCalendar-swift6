# FSCalendar — Swift 6

A UIKit calendar with a Foundation date engine. Requires Swift 6.2 or later, Swift 6 language mode, and iOS 16 or later. The package contains no SwiftUI, networking, third-party runtime dependency, or Objective-C forwarding.

| SwiftPM product | Contents |
| --- | --- |
| `FSCalendarCore` | Civil dates, page/occurrence identities, Gregorian grids, inclusive bounds, ordered selection transactions |
| `FSCalendar` | Main-actor UIKit view, custom collection layout, reusable cells, appearance, gestures, interactive transitions |

Add this directory as a local package in Xcode, or add its Git URL after publishing the repository. Link both products to your UIKit app. The Foundation core also supports macOS 13+ for host-side tests; the view requires UIKit.

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

Open `Example/CalendarShowcase.xcodeproj`, select **CalendarShowcase**, and run Calendar Lab. Its implementation selector switches between the real vendored Objective-C reference and the Swift rewrite. Eighteen scenarios demonstrate paging, continuous sticky headers, selection, placeholders, bounds, custom content/cells, range picking, transitions above a list, sizing, RTL, large text, and dark appearance.

```sh
swift test
./Scripts/test-device.sh YOUR_DEVICE_UDID comparison -collect-test-diagnostics never
```

The device script runs both configurations and saves results under ignored `artifacts/`. A successful run leaves the demo installed and opens its scenario list. The legacy physical-device baseline passed before implementation of the Swift products began.

See [migration/customization](Documentation/MIGRATION.md), [contracts](Documentation/CONTRACTS.md), [testing](Documentation/TESTING.md), and [actual validation results](Documentation/VALIDATION.md). iOS 16 runtime compatibility remains a separate release check from the iOS 17.7.2 physical-device suite.

## License

MIT; see [LICENSE](LICENSE). The development reference retains original attribution and [source hashes](Development/Legacy/README.md). Legacy code and adapters are outside every distributed SwiftPM target. The upstream checkout was not modified.
