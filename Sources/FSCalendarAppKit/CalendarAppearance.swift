#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

public typealias CalendarScrollAxis = FSCalendarCore.CalendarScrollAxis
public typealias CalendarDisplayMode = FSCalendarCore.CalendarDisplayMode
public typealias CalendarTransitionState = FSCalendarCore.CalendarTransitionState
public typealias DayState = FSCalendarCore.DayState

@MainActor public struct FSCalendarAppearance {
    public var titleColor: NSColor = .labelColor
    public var placeholderColor: NSColor = .tertiaryLabelColor
    public var disabledColor: NSColor = .tertiaryLabelColor
    public var selectionColor: NSColor = .systemIndigo
    public var selectedTitleColor: NSColor = .white
    public var todayColor: NSColor = .systemOrange
    public var subtitleColor: NSColor = .secondaryLabelColor
    public var eventColor: NSColor = .systemIndigo
    public var headerColor: NSColor = .labelColor
    public var backgroundColor: NSColor = .controlBackgroundColor
    public var titleFont: NSFont = .systemFont(ofSize: 15)
    public var subtitleFont: NSFont = .systemFont(ofSize: 10)
    public var headerFont: NSFont = .boldSystemFont(ofSize: 16)
    public var weekdayFont: NSFont = .systemFont(ofSize: 12)
    public var rowHeight: CGFloat = 44
    public var headerHeight: CGFloat = 44
    public var weekdayHeight: CGFloat = 26
    public init() {}

    func resolved() -> Self {
        func dimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
            value.isFinite ? min(1000, max(0, value)) : fallback
        }
        var copy = self
        copy.rowHeight = max(dimension(rowHeight, fallback: 44), titleFont.pointSize + subtitleFont.pointSize + 16)
        copy.headerHeight = max(dimension(headerHeight, fallback: 44), headerFont.pointSize + 16)
        copy.weekdayHeight = max(dimension(weekdayHeight, fallback: 26), weekdayFont.pointSize + 10)
        return copy
    }
}

@MainActor public struct DayContent {
    public var title: String?
    public var subtitle: String?
    public var image: NSImage?
    public var numberOfEvents: Int
    public var accessibilityLabel: String?
    public var accessibilityValue: String?
    public init(title: String? = nil, subtitle: String? = nil, image: NSImage? = nil, numberOfEvents: Int = 0,
                accessibilityLabel: String? = nil, accessibilityValue: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.image = image; self.numberOfEvents = max(0, numberOfEvents)
        self.accessibilityLabel = accessibilityLabel; self.accessibilityValue = accessibilityValue
    }
}
@MainActor public struct DayAppearance {
    public var titleColor: NSColor?
    public var subtitleColor: NSColor?
    public var fillColor: NSColor?
    public var selectedFillColor: NSColor?
    public var borderColor: NSColor?
    public var eventColor: NSColor?
    /// Nil uses a circle; zero uses a square.
    public var cornerRadius: CGFloat?
    public init(titleColor: NSColor? = nil, subtitleColor: NSColor? = nil, fillColor: NSColor? = nil,
                selectedFillColor: NSColor? = nil, borderColor: NSColor? = nil,
                eventColor: NSColor? = nil, cornerRadius: CGFloat? = nil) {
        self.titleColor = titleColor; self.subtitleColor = subtitleColor; self.fillColor = fillColor
        self.selectedFillColor = selectedFillColor; self.borderColor = borderColor
        self.eventColor = eventColor; self.cornerRadius = cornerRadius
    }
}
@MainActor public protocol FSCalendarDataSource: AnyObject {
    func calendar(_ calendar: FSCalendarView, contentFor day: CivilDay) -> DayContent
    func calendar(_ calendar: FSCalendarView, appearanceFor day: CivilDay) -> DayAppearance
    func calendar(_ calendar: FSCalendarView, reuseIdentifierFor day: CivilDay) -> String?
}
public extension FSCalendarDataSource {
    func calendar(_ calendar: FSCalendarView, contentFor day: CivilDay) -> DayContent { DayContent() }
    func calendar(_ calendar: FSCalendarView, appearanceFor day: CivilDay) -> DayAppearance { DayAppearance() }
    func calendar(_ calendar: FSCalendarView, reuseIdentifierFor day: CivilDay) -> String? { nil }
}
@MainActor public protocol FSCalendarDelegate: AnyObject {
    func calendar(_ calendar: FSCalendarView, shouldApply change: SelectionChange) -> Bool
    func calendar(_ calendar: FSCalendarView, didChangeSelection change: SelectionChange)
    func calendarCurrentPageDidChange(_ calendar: FSCalendarView)
    func calendar(_ calendar: FSCalendarView, didChangeDisplayMode mode: CalendarDisplayMode)
    func calendar(_ calendar: FSCalendarView, preferredHeightDidChange height: CGFloat, animated: Bool)
}
public extension FSCalendarDelegate {
    func calendar(_ calendar: FSCalendarView, shouldApply change: SelectionChange) -> Bool { true }
    func calendar(_ calendar: FSCalendarView, didChangeSelection change: SelectionChange) {}
    func calendarCurrentPageDidChange(_ calendar: FSCalendarView) {}
    func calendar(_ calendar: FSCalendarView, didChangeDisplayMode mode: CalendarDisplayMode) {}
    func calendar(_ calendar: FSCalendarView, preferredHeightDidChange height: CGFloat, animated: Bool) {}
}
#endif
