#if canImport(UIKit)
import UIKit
import FSCalendarCore

public typealias CalendarScrollAxis = FSCalendarCore.CalendarScrollAxis
public typealias CalendarDisplayMode = FSCalendarCore.CalendarDisplayMode
public typealias CalendarTransitionState = FSCalendarCore.CalendarTransitionState
public typealias DayState = FSCalendarCore.DayState

@MainActor public struct FSCalendarAppearance {
    public var titleColor: UIColor = .label
    public var placeholderColor: UIColor = .tertiaryLabel
    public var disabledColor: UIColor = .tertiaryLabel
    public var selectionColor: UIColor = .systemIndigo
    public var selectedTitleColor: UIColor = .white
    public var todayColor: UIColor = .systemOrange
    public var subtitleColor: UIColor = .secondaryLabel
    public var eventColor: UIColor = .systemIndigo
    public var headerColor: UIColor = .label
    public var backgroundColor: UIColor = .secondarySystemGroupedBackground
    public var titleFont: UIFont = .preferredFont(forTextStyle: .body)
    public var subtitleFont: UIFont = .preferredFont(forTextStyle: .caption2)
    public var headerFont: UIFont = .preferredFont(forTextStyle: .headline)
    public var weekdayFont: UIFont = .preferredFont(forTextStyle: .caption1)
    public var rowHeight: CGFloat = 44
    public var headerHeight: CGFloat = 44
    public var weekdayHeight: CGFloat = 26
    public init() {}

    // Resolve preferred fonts against the calendar's traits, including container overrides.
    func resolved(for traits: UITraitCollection) -> Self {
        func font(_ value: UIFont) -> UIFont {
            guard let style = value.fontDescriptor.object(forKey: .textStyle) as? String else { return value }
            return .preferredFont(forTextStyle: UIFont.TextStyle(rawValue: style), compatibleWith: traits)
        }
        func dimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
            value.isFinite ? min(1000, max(0, value)) : fallback
        }
        var copy = self
        copy.titleFont = font(titleFont); copy.subtitleFont = font(subtitleFont)
        copy.headerFont = font(headerFont); copy.weekdayFont = font(weekdayFont)
        copy.rowHeight = dimension(rowHeight, fallback: 44)
        copy.headerHeight = dimension(headerHeight, fallback: 44)
        copy.weekdayHeight = dimension(weekdayHeight, fallback: 26)
        return copy
    }
}

@MainActor public struct DayContent {
    public var title: String?
    public var subtitle: String?
    public var image: UIImage?
    public var numberOfEvents: Int
    public var accessibilityLabel: String?
    public var accessibilityValue: String?
    public init(title: String? = nil, subtitle: String? = nil, image: UIImage? = nil, numberOfEvents: Int = 0,
                accessibilityLabel: String? = nil, accessibilityValue: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.image = image; self.numberOfEvents = max(0, numberOfEvents)
        self.accessibilityLabel = accessibilityLabel; self.accessibilityValue = accessibilityValue
    }
}
@MainActor public struct DayAppearance {
    public var titleColor: UIColor?
    public var subtitleColor: UIColor?
    public var fillColor: UIColor?
    public var selectedFillColor: UIColor?
    public var borderColor: UIColor?
    public var eventColor: UIColor?
    /// Nil uses a circle; zero uses a square.
    public var cornerRadius: CGFloat?
    public init(titleColor: UIColor? = nil, subtitleColor: UIColor? = nil, fillColor: UIColor? = nil,
                selectedFillColor: UIColor? = nil, borderColor: UIColor? = nil,
                eventColor: UIColor? = nil, cornerRadius: CGFloat? = nil) {
        self.titleColor = titleColor; self.subtitleColor = subtitleColor; self.fillColor = fillColor
        self.selectedFillColor = selectedFillColor; self.borderColor = borderColor
        self.eventColor = eventColor; self.cornerRadius = cornerRadius
    }
}
@MainActor public protocol FSCalendarDataSource: AnyObject {
    func calendar(_ calendar: FSCalendar, contentFor day: CivilDay) -> DayContent
    func calendar(_ calendar: FSCalendar, appearanceFor day: CivilDay) -> DayAppearance
    func calendar(_ calendar: FSCalendar, reuseIdentifierFor day: CivilDay) -> String?
}
public extension FSCalendarDataSource {
    func calendar(_ calendar: FSCalendar, contentFor day: CivilDay) -> DayContent { DayContent() }
    func calendar(_ calendar: FSCalendar, appearanceFor day: CivilDay) -> DayAppearance { DayAppearance() }
    func calendar(_ calendar: FSCalendar, reuseIdentifierFor day: CivilDay) -> String? { nil }
}
@MainActor public protocol FSCalendarDelegate: AnyObject {
    func calendar(_ calendar: FSCalendar, shouldApply change: SelectionChange) -> Bool
    func calendar(_ calendar: FSCalendar, didChangeSelection change: SelectionChange)
    func calendarCurrentPageDidChange(_ calendar: FSCalendar)
    func calendar(_ calendar: FSCalendar, didChangeDisplayMode mode: CalendarDisplayMode)
    func calendar(_ calendar: FSCalendar, preferredHeightDidChange height: CGFloat, animated: Bool)
}
public extension FSCalendarDelegate {
    func calendar(_ calendar: FSCalendar, shouldApply change: SelectionChange) -> Bool { true }
    func calendar(_ calendar: FSCalendar, didChangeSelection change: SelectionChange) {}
    func calendarCurrentPageDidChange(_ calendar: FSCalendar) {}
    func calendar(_ calendar: FSCalendar, didChangeDisplayMode mode: CalendarDisplayMode) {}
    func calendar(_ calendar: FSCalendar, preferredHeightDidChange height: CGFloat, animated: Bool) {}
}
#endif
