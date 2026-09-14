# Migration and customization

This is a source rewrite with explicit Swift contracts, not a drop-in binary replacement. Import `FSCalendar` for UIKit and `FSCalendarCore` for dates/configuration. UIKit APIs, delegates, data sources, and appearance values are main-actor isolated. Content callbacks are synchronous; load asynchronously in your application, then reload affected days on the main actor.

## API mapping

| Objective-C API | Swift API |
| --- | --- |
| Bounds, firstWeekday, locale, timeZone | Construct `CalendarConfiguration`, then `try apply(configuration:)` |
| `placeholderType` | Configuration `placeholders: .none / .variable / .sixRows` |
| `allowsSelection`, `allowsMultipleSelection` | Configuration `selectionMode: .disabled / .single / .multiple` |
| `scope`, `scrollDirection`, `pagingEnabled` | `setDisplayMode` with `.month(.horizontal)`, `.month(.vertical)`, `.week`, or `.continuousMonths` |
| `setCurrentPage`, `select`, `deselect` | Throwing methods; use `CivilDay` or supported `Date` overloads |
| `selectedDates` | `selectedDays` preserves civil identity/order; `selectedDates` resolves instants in the configured zone |
| `reloadData` | `reloadData()` or `reload(dates: Set<CivilDay>)` |
| `boundingRectWillChange` | `preferredHeightDidChange`; paged views also supply intrinsic height and `sizeThatFits` |
| `swipeToChooseGesture` | `swipeSelectionEnabled` |
| External scope pan | `handleScopeGesture(_:)`; disable the internal `scopeGestureEnabled` when forwarding a container pan |
| Custom cell dequeue | Register the subclass, then return its reuse identifier from the data source |

For configuration changes, construct a new value preserving fields you wish to retain. Switching to single selection keeps the latest valid day. Bounds/time-zone changes prune selections that are no longer valid. Pruning bypasses vetoes and emits one `.configuration` change when necessary.

## Dates and placeholders

The Foundation product can be used without constructing a view:

```swift
import Foundation
import FSCalendarCore

let engine = try CalendarEngine(configuration: CalendarConfiguration(
    firstWeekday: 2, timeZone: TimeZone(secondsFromGMT: 0)!
))
let grid = try engine.grid(containing: CivilDay(year: 2024, month: 2, day: 14), scope: .month)
let visibleDays = grid.occurrences.filter { !$0.isHidden }.map(\.day)
```

`CivilDay` is a Gregorian year/month/day independent of time of day. `date(in:)` returns the first valid instant of that day and throws for a skipped civil day. DST days are not assumed to contain 86,400 seconds. Grids retain weekday slots for skipped days and make those cells unselectable.

Selection bounds are inclusive. Navigation accepts any day whose month/week intersects the range; a page anchor may precede the minimum selectable day. `currentPage` is the first day of the month or configured week. Selection still rejects individual out-of-range days.

`CellOccurrenceID` combines a `PageID` and `CivilDay`. A day may appear in its own month and an adjacent page. Selection and targeted reload refresh visible occurrences; prefetched cells refresh when displayed.

Six-row months contain 42 slots. An aligned month starts in row one, without the legacy extra preceding week. `.variable` uses the occupied 4–6 rows; `.none` preserves weekday slots but hides adjacent-month dates. Week pages contain seven current occurrences and page horizontally.

## Selection callbacks

Requests follow validation → veto → atomic commit → one callback. `SelectionChange` contains ordered additions, removals, resulting selection, and origin. Invalid requests throw typed errors without changing selection. No-op requests emit nothing. Vetoes throw `.selectionVetoed` programmatically and restore displayed state for gestures.

Do not mutate selection, configuration, page, or mode inside a selection callback; reentry throws `.reentrantMutation`. Schedule a subsequent main-actor operation if needed and check its source selection is still current. The range demo demonstrates this. Range picking and lunar subtitles are application samples, not additional engine modes.

## Content and cells

Keep the data source strongly owned by your controller; the calendar holds it weakly.

```swift
@MainActor
final class CalendarContent: FSCalendarDataSource {
    func calendar(_ calendar: FSCalendar, contentFor day: CivilDay) -> DayContent {
        DayContent(title: day.day == 1 ? "1st" : nil,
                   subtitle: day.day == 14 ? "Birthday" : nil,
                   image: day.day == 14 ? UIImage(systemName: "heart.fill") : nil,
                   numberOfEvents: day.day == 14 ? 2 : 0)
    }
    func calendar(_ calendar: FSCalendar, appearanceFor day: CivilDay) -> DayAppearance {
        DayAppearance(titleColor: day.day == 14 ? .systemPink : nil)
    }
}
```

Subclass `FSCalendarCell` and override `apply(content:state:appearance:style:)`, calling `super`. Override `layoutSubviews()` for custom geometry. Labels, image view, selection background, and read-only `dayState` are public. Register the subclass and return its identifier from `calendar(_:reuseIdentifierFor:)`. Reset additional subclass state on reuse. Unknown identifiers fall back to the default cell.

Appearance is separate from configuration. Modify a copy of `calendar.appearance`, then assign it back. Preferred text-style fonts resolve against the view's content-size traits; explicit custom fonts keep their point size. Row height scales with Dynamic Type. Honor preferred-height callbacks or use a scrolling container. Nonfinite dimensions fall back to defaults; finite dimensions are clamped to 0...1000 points before text minimums/scaling.

Cells expose localized full dates, selected/disabled traits, and subtitle/event information. Supply `DayContent.accessibilityLabel` and `accessibilityValue` for application-specific/localized announcements. Default event/today words are English. Weekdays expose full localized names. Default colors are dynamic system colors; custom color contrast remains the application's responsibility.

## Transitions and sizing

Transitions anchor to the latest selected visible day, then visible today, then the first in-range visible day. Public mode/page commit on completion. `beginInteractiveTransition(to:)`, `updateInteractiveTransition(progress:)`, and `finishInteractiveTransition(commit:animated:)` support custom gesture coordinators. Interactive transitions are month ↔ week; use `setDisplayMode` for other changes.

Cancellation restores source mode/page/height. Replacement cancels and restarts toward the latest target. External resizing/configuration changes cancel before relayout. Reduce Motion suppresses settling animation. In constrained containers update the height constraint inside `preferredHeightDidChange`; interactive callbacks supply intermediate heights.

Continuous mode has pinned month headers and requires a viewport height; it has no intrinsic height for the complete date range. Detailed grids use a nine-page LRU cache. Lightweight section geometry covers the range; item attributes are computed around the visible rectangle.

## Compatibility

Gregorian is the only grid calendar. Derive lunar subtitles in your data source rather than changing the grid calendar. See `VALIDATION.md` for exact compiler/device evidence and outstanding release checks.
