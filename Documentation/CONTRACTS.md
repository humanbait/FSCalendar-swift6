# Swift calendar contracts

The rewrite preserves shared capabilities while making the following deliberate API and behavior changes. The legacy column documents historical upstream behavior; regression tests enforce the Swift contract. The vendored reference and its characterization tests have been removed.

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

## Continuous months

`.continuousMonths` presents one uninterrupted grid of civil weeks in UIKit and AppKit.
Each month supplies only its own dates, with `.current` occurrence position and its actual
month as the page identity. Neighboring months share a boundary row; no date is repeated.
Placeholder settings, including six-row padding, apply only to paged month presentation.
The first and last months remain complete: dates outside selection bounds are disabled,
and unused weekday slots at the outer edges are blank.

Continuous mode has no month/year heading or reserved heading space. The weekday labels
stay above the grid. Each month's first day shows its localized short standalone month
name (for example, `Jan` or `Feb`) instead of `1`, using the normal title styling.
A non-nil `DayContent.title`, including an empty string, takes precedence. Subtitles,
images, and full-date accessibility labels retain their usual behavior. Changing the
configuration locale refreshes the month names.

UIKit and AppKit show a four-digit year below automatic month names outside the current
Gregorian year in the configured time zone. The year uses subtitle styling and is
omitted when a custom title or any non-nil subtitle (including an empty string) is
supplied. The reference year comes from the clock, independently of the overridable
`today` highlight; visible labels refresh on significant time changes and activation.
The month/year group is centered, and its year fades with continuous/week transitions.
When an automatic year is visible, its event dots follow the year on the same line,
with a 3-point gap. The year stays centered under the month when space permits, and dots mirror in RTL.
Other subtitles and ordinary dates retain their below-text event placement. Dots
outside the selection fill retain the normal event color for visibility.
AppKit also refreshes after wake and fits automatic month/year text to narrow columns
from the original configured fonts, avoiding cumulative shrinking on resize.

A one-physical-pixel separator follows each internal month boundary: below the previous
month's cells, beside the first new-month cell, and above the remaining cells in the row.
The two bends use an 8-point radius, clamped to the available horizontal runs and half
of the row height. Set `FSCalendarAppearance.monthSeparatorCornerRadius` to zero for
square bends. Negative radii resolve to zero; nonfinite values resolve to the default.
Months starting in the first weekday column get a straight line above that row. No rule
is drawn before the first displayed month or after the last. Layout decorations draw
above selection backgrounds without intercepting input or exposing accessibility elements,
including for custom cells. `FSCalendarAppearance.monthSeparatorColor` defaults to the
platform's semantic separator color. Geometry mirrors in RTL and follows resizing and
display scale; colors follow appearance changes.

Month backgrounds follow the same rounded boundary paths beneath date cells and selections.
Odd-numbered months use `backgroundColor`; even-numbered months use
`alternatingMonthBackgroundColor`, an adaptive neutral gray (0.95 white in light appearance,
0.16 in dark appearance). Set the latter to `nil` to use `backgroundColor` throughout.
Month parity is independent of the configured range and remains stable across year changes.
Outer empty weekday slots and trailing scroll space retain the calendar background.
Both fills and rules fade with continuous/week scope transitions; neither decoration
intercepts input or adds accessibility elements. Custom cells with opaque backgrounds
can cover the month fill. Paged month and week modes do not create these decorations.

`currentPage` identifies the latest month whose first week has reached the viewport top,
including a partially visible boundary week. `setCurrentPage` and month navigation align
that first week at the top. Trailing scroll space lets the final month reach the same alignment in tall viewports.
Paged month and week modes restore the heading and numeric first-day titles.
RTL mirrors weekday columns without changing chronological row order. A viewport height
is still required; continuous mode has no intrinsic height for the entire range.

`CalendarEngine.continuousMonthSections()` returns lightweight `ContinuousMonthSection`
values (`page`, `startSlot`, `dayCount`, `firstRow`, `rowCount`). Slots are measured from the
week containing the first displayed month. `continuousMonthGrid(containing:)` returns
only the requested month's dates; its row count includes shared boundary rows, so its
occurrence count is not necessarily `rowCount * 7`. Existing month/week grid APIs retain
their padded grids. Renderers retain at most nine detailed month grids.

## Selection transaction

Validate the complete proposed selection, consult a synchronous veto, commit once, update all visible occurrences, and issue one change notification. Changes carry additions, removals, resulting order, and user/programmatic/configuration origin. Reentrant mutation during a transaction must be rejected explicitly. Configuration pruning is mandatory and bypasses vetoes.

## Transition state

Idle, interactive, and settling states retain source/target mode, source/target page, anchor day, and progress. Public mode and page commit on completion. Cancellation restores the source; a replacement request cancels the previous transition before starting the new one. During a UIKit continuous-month/week animation, requesting the source reverses the current animator and requesting its existing destination is a no-op. Configuration and geometry changes cancel before applying new state.

## UIKit animation integration

Accepted additions to the selection bounce visible selection circles for 0.15 seconds, including programmatic selection. Reloading existing selection does not replay the animation. Deselection and reuse clear it.

Variable-row month height changes and month/week scope transitions use 0.3-second ease-in-out animation. Paged swipes update the destination page and start resizing at drag release, alongside deceleration; scroll completion only reconciles an interrupted or changed destination. Scope transitions keep the focused row opaque while surrounding rows fade; interactive dragging drives height, row position, and opacity together. Reduce Motion and nonanimated requests apply final geometry immediately.

UIKit continuous-month/week transitions use the same focused-week motion, including weeks shared by adjacent month sections. They start at the actual viewport height and fractional scroll offset; returning to continuous mode restores its most recently laid-out viewport height. The header, weekdays, month separators and short-month labels transition within the same animation. Continuous mode still has no intrinsic viewport height, and interactive scope gestures remain unsupported there.

In `calendar(_:preferredHeightDidChange:animated:)`, update the application's height constraint and call its container's `layoutIfNeeded()` synchronously. Animated notifications run inside the calendar's animation context; starting another animation in the delegate can desynchronize the surrounding layout. Interactive notifications carry `animated == false`. Identical heights remain suppressed per delegate, and initial paged layout uses `preferredHeight` directly. Hosts that supply a fixed continuous viewport must forward transition heights while `transitionState` is active; reapplying the fixed height during the animation prevents the container from moving with its rows. The connected-range example restores its 400-point viewport without a second completion resize.

## Defaults

iOS 16+, Swift 6 language mode, Swift 6.2 minimum toolchain, SwiftPM source distribution. Gregorian grids, Sunday first, current locale/time zone, horizontal month pages, single selection, six rows, and inclusive bounds 1970-01-01 through 2099-12-31.
