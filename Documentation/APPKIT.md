# Native AppKit integration

`FSCalendarAppKit` is a native macOS 13+ library built with Swift 6 language mode and a
Swift 6.2 minimum manifest. Link `FSCalendarAppKit` and `FSCalendarCore` from the local
package or its published Git location. It has no SwiftUI, Catalyst, legacy adapter,
networking, or third-party runtime dependency.

```swift
import AppKit
import FSCalendarAppKit
import FSCalendarCore

@MainActor
final class CalendarController: NSViewController, FSCalendarDelegate {
    let calendar = FSCalendarView(frame: .zero)
    var height: NSLayoutConstraint!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        calendar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(calendar)
        height = calendar.heightAnchor.constraint(equalToConstant: calendar.preferredHeight)
        NSLayoutConstraint.activate([
            calendar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            calendar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            calendar.topAnchor.constraint(equalTo: view.topAnchor), height
        ])
        calendar.delegate = self
    }
    func calendar(_ calendar: FSCalendarView, preferredHeightDidChange value: CGFloat, animated: Bool) {
        height.constant = value
        view.layoutSubtreeIfNeeded()
    }
}
```

For continuous months, constrain a viewport height; intrinsic height is unspecified.
For paged modes, use intrinsic/fitting height or the preferred-height callback. Both
`init(frame:)` and `init(coder:)` work; in Interface Builder use class `FSCalendarView`
and module `FSCalendarAppKit`.

## API mapping

| UIKit | AppKit |
| --- | --- |
| `FSCalendar: UIView` | `FSCalendarView: NSView` |
| `appearance: FSCalendarAppearance` | `calendarAppearance: FSCalendarAppearance` |
| `UIColor`, `UIFont`, `UIImage` | `NSColor`, `NSFont`, `NSImage` |
| `FSCalendarCell: UICollectionViewCell` | `FSCalendarItem: NSCollectionViewItem` |
| `register(_:forCellReuseIdentifier:)` | `register(_:forItemReuseIdentifier:)` |
| `handleScopeGesture(UIPanGestureRecognizer)` | `handleScopeGesture(NSPanGestureRecognizer)` |
| Dynamic Type | Explicit AppKit font scaling |
| Touch swipe selection | Mouse-drag selection (`swipeSelectionEnabled`) |
| Rotation | Window/live resize and backing-scale changes |

`NSView.appearance` keeps its native role: set `NSAppearance(named: .darkAqua)` to force
dark mode. Calendar colors/fonts belong to `calendarAppearance`. `CalendarScrollAxis`,
`CalendarDisplayMode`, `CalendarTransitionState` and `DayState` live in the shared core;
explicit UIKit type aliases preserve existing source names.

Configuration, day/Date navigation, ordered selection, delegate veto, atomic callback,
no-op suppression, typed errors, configuration pruning, targeted `reload(dates:)` and
`reloadData()` follow the Swift UIKit contracts. The same development-only assertions
run against both renderers. The ordered latest valid day survives a switch to single
selection. Bounds are inclusive. Conventional six rows do not insert an extra preceding
week when the month starts on the first weekday.

## Desktop interaction

Single-selection clicks replace the selection. Multiple-selection clicks toggle one
day; Command and Shift do not change this policy. Disabled selection prevents activation.
Dragging paints additions or removals according to the first date and visits each date
at most once per gesture. Focus is independent: `focusedDay` is read-only and
`try focus(day)` validates the day, brings it into view and leaves selection alone. In continuous mode an already visible day keeps the scroll position, including across month boundaries.

Arrow keys move focus by one day or week, with horizontal arrows respecting RTL. Space
activates the focused day. Page Up/Down navigate pages. Tab and Shift-Tab leave the calendar
normally. Focus remains exposed to accessibility, but cells do not draw a rectangular
keyboard-focus outline. Set `userInterfaceLayoutDirection = .rightToLeft` for explicit RTL.

Paged trackpad input accumulates and snaps once scrolling settles. Continuous months use
native NSScrollView scrolling and shared boundary weeks with no repeated dates. Weekday
labels remain visible; the month/year heading is hidden without reserving its height.
First days use localized short month names, and rounded stepped lines separate months.
Continuous rows center the text group and selection/today circle without enlarging the
circle. Automatic month labels outside the current Gregorian year show a four-digit
year underneath, using subtitle styling (selected-title color when selected). A custom
title or any non-nil subtitle, including an empty string, suppresses the automatic year.
The reference year uses the actual clock in the configured time zone, independently
of `today`, and refreshes on day/clock changes, activation, wake, and configuration updates.
Clock and wake observers deliver on `OperationQueue.main` before entering the main actor,
including notifications posted from background threads. Their weak captures do not retain
the view; its isolated deinitializer removes the retained tokens from their original centers.
See Apple's [notification delivery contract](https://developer.apple.com/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:)).
The year fades and its occupied space follows continuous/week transition progress.
Automatic month/year fonts fit narrow columns and larger configured fonts without
cumulative shrinkage on resize. Events follow automatic years on the same line with
a 3-point gap; the year stays centered where space permits and dots mirror in RTL. Other cells keep
below-text dots. Dots outside a selected fill use the normal event color to remain visible. Paged month/week geometry is unchanged.
Set `calendarAppearance.monthSeparatorColor` and `monthSeparatorCornerRadius` (default 8;
zero for square bends) to customize the rules. Odd months use `backgroundColor`; even
months use the adaptive neutral `alternatingMonthBackgroundColor`. Set the latter to
`nil` for a uniform background. Both fills and rules follow scope animations and theme
changes. Explicit `DayContent.title` values override month names. Heavy day grids use an LRU cache
capped at nine pages; section frames/row counts stay lightweight. Day accessibility IDs
contain the civil date, month position and page anchor, so placeholders are distinguishable.

## Content and customization

Keep a strong reference to your data source and delegate; the calendar's references are weak.
Data-source methods synchronously supply `DayContent`, `DayAppearance`, and an optional reuse
identifier. An unknown identifier uses the default item. Empty registration identifiers throw.

```swift
@MainActor final class RoundedItem: FSCalendarItem {
    override func apply(content: DayContent, state: DayState,
                        appearance: FSCalendarAppearance, style: DayAppearance) {
        var rounded = style
        rounded.cornerRadius = 8
        super.apply(content: content, state: state, appearance: appearance, style: rounded)
        titleLabel.font = .boldSystemFont(ofSize: 17)
    }
}
try calendar.register(RoundedItem.self, forItemReuseIdentifier: "rounded")
```

Call `super.apply` and reset every custom field on reuse. Defaults reset title, subtitle,
image, events, styling and accessibility. `DayState` identifies both the
civil day and its page-specific occurrence. Reloading a date updates all visible occurrences.
Lunar dates remain supplied subtitles. The range demo derives its range from multiple
selection and applies it on the next main-actor turn, after the selection callback finishes.

## Transitions and list coordination

`setDisplayMode(_:animated:)`, `beginInteractiveTransition(to:)`,
`updateInteractiveTransition(progress:)`, and `finishInteractiveTransition(commit:animated:)`
expose idle, interactive and settling states. Public page/mode stay at the source until
completion. Cancellation restores the source. Paged-mode replacement cancels and restarts. Resizing
or changing configuration cancels before rebuilding. Anchoring uses the latest selected
visible day, then visible today, then the first eligible visible day.

Continuous-month ↔ week switching uses one reversible 0.3-second ease-in-out timeline.
The anchor week stays opaque and moves as a single row, even across month sections.
Height starts at the actual viewport and expansion restores its remembered height;
the connected-range showcase uses 420 points. The heading and weekday labels move
with the viewport while surrounding rows, separators and short month titles fade.
The destination grid replaces the rendering grid at matching geometry. Repeating a
destination does nothing; requesting the opposite destination reverses the current
timeline. Height callbacks report each transition frame, so containers should apply
those heights synchronously without an additional animation or completion resize.
Continuous mode remains button-only; the interactive gesture API is for paged scopes.

Forward a dedicated `NSPanGestureRecognizer` from a scope handle above a list. Do not attach
it to ordinary list scrolling. The demo shows this separation. A main-actor animation driver
uses elapsed monotonic time to interpolate the native view geometry; cancellation prevents
stale completion. There are no threaded NSAnimation callbacks or unsafe isolation escapes.
The control reads and observes AppKit's Reduce Motion preference and completes settlement
immediately when enabled.

## Development and validation

```sh
./script/build_and_run.sh --verify
./Scripts/test-macos.sh --destination 'platform=macOS,arch=arm64'
# Use platform=macOS,id=YOUR_MAC_ID for a particular Mac.
# Launch a fixed scenario directly:
open -n artifacts/mac-run/Build/Products/Debug/CalendarShowcaseMac.app --args --scenario content
```

The Mac scheme in `Example/CalendarShowcase.xcodeproj` links local SwiftPM library products.
Shared demo fixtures and test assertions are development-only targets, never runtime product
dependencies. `Scripts/generate_project.py` regenerates both platforms' checked-in project
and schemes. `CalendarShowcaseMac.xctestplan` is independent of the UIKit test plan.

See [recorded results and release gates](MACOS-VALIDATION.md). Mac timing samples are only
compared with runs on the same Mac, never with the iPhone baseline.

Implementation references: Apple's [collection-view architecture](https://developer.apple.com/documentation/appkit/nscollectionview),
[custom layout content size](https://developer.apple.com/documentation/appkit/nscollectionviewlayout/collectionviewcontentsize),
and [Reduce Motion preference](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion).


## Background clock delivery validation — 2026-11-14

PowerTask's native background-notification checks exposed a Swift actor-isolation
trap in the selector-based clock observer at revision
`4860b0ae0de2faaec0ff5557f455c8cff3974a68`. The observer now delivers clock and wake
callbacks on the main queue before touching AppKit, preserving the existing
Today/year refresh and scroll position.

With Xcode 27.2 (27B52), Swift 6.4.2, and macOS 27.2 on arm64,
`swift test -Xswiftc -warnings-as-errors` passed all 49 host-compatible tests
(20 Core and 29 AppKit). The rollover test posts day, clock, time-zone, activation,
and workspace-wake notifications from a background queue, verifies Today/year
labels and stable scroll position, and the lifetime test posts after disposal.
PowerTask's 12 focused native checks also passed with this local dependency and
Main Thread Checker configured to crash on a report. No checker reports occurred.

Validation source blobs:

- `FSCalendarView.swift`: `46197bfb01dbc14028c69b0b3bb29e2a4bf91b48`
- `CalendarContentTests.swift`: `a90145fb5ce8667ef1127d296ffe7dd8a2bc177b`

Local evidence: `/private/tmp/fscalendar-midnight-tests.log`,
`/private/tmp/mac-midnight-tests-dependency.log`, and
`/private/tmp/MacMidnightTestsDependency.xcresult`. Notifications were injected;
no system-clock changes, overnight observation, simulator tests, or new physical
iOS validation were performed for this AppKit-only correction.
