# Swift calendar contracts

The rewrite preserves shared capabilities while making the following deliberate API and behavior changes. Legacy characterization tests remain intact; new-contract tests must not silently change their expected results.

| Behavior | Legacy reference | Swift contract |
| --- | --- | --- |
| Programmatic selection | Does not call the selection delegate on the current-month path | Same validated transaction and single change callback as user selection |
| Invalid selection | Objective-C exception | Typed `CalendarError`, state unchanged |
| Duplicate selection | No additional selected date | No state change and no callback |
| Multiple selection order | Order of first selection | Retained; last remaining selected day is `selectedDate` |
| Aligned six-row month | Adds the preceding week | Begins in the first occupied week; trailing placeholders fill 42 slots |
| Cancelled scope gesture | Can commit the target scope | Restores the source mode, page, and height |
| Week page identity | May identify a middle day | Canonical first day of the week |
| Configuration changes | Independent mutable properties | Validated, atomic application with selection pruning |

## Ownership

`FSCalendarCore` uses immutable date/page models and value-based selection state. Day identity is distinct from page-specific occurrence identity. Calculations use calendar units, explicit time zones, and calendar start-of-day operations.

`FSCalendar` and its UIKit callbacks are main-actor isolated. Content providers remain synchronous. Applications own asynchronous loading and call targeted reloads after updating their data.

## Selection transaction

Validate the complete proposed selection, consult a synchronous veto, commit once, update all visible occurrences, and issue one change notification. Changes carry additions, removals, resulting order, and user/programmatic/configuration origin. Reentrant mutation during a transaction must be rejected explicitly. Configuration pruning is mandatory and bypasses vetoes.

## Transition state

Idle, interactive, and settling states retain source/target mode, source/target page, anchor day, and progress. Public mode and page commit on completion. Cancellation restores the source; a replacement request cancels the previous transition before starting the new one. Configuration and geometry changes cancel before applying new state.

## UIKit animation integration

Accepted additions to the selection bounce visible selection circles for 0.15 seconds, including programmatic selection. Reloading existing selection does not replay the animation. Deselection and reuse clear it.

Variable-row month height changes and month/week scope transitions use 0.3-second ease-in-out animation. Paged swipes update the destination page and start resizing at drag release, alongside deceleration; scroll completion only reconciles an interrupted or changed destination. Scope transitions keep the focused row opaque while surrounding rows fade; interactive dragging drives height, row position, and opacity together. Reduce Motion and nonanimated requests apply final geometry immediately.

In `calendar(_:preferredHeightDidChange:animated:)`, update the application's height constraint and call its container's `layoutIfNeeded()` synchronously. Animated notifications run inside the calendar's animation context; starting another animation in the delegate can desynchronize the surrounding layout. Interactive notifications carry `animated == false`. Identical heights remain suppressed per delegate, and initial layout uses `preferredHeight` directly.

## Defaults

iOS 16+, Swift 6 language mode, Swift 6.2 minimum toolchain, SwiftPM source distribution. Gregorian grids, Sunday first, current locale/time zone, horizontal month pages, single selection, six rows, and inclusive bounds 1970-01-01 through 2099-12-31.
