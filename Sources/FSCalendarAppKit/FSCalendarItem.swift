#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Subclass this item and override apply to customize day rendering. Always call super.
@MainActor open class FSCalendarItem: NSCollectionViewItem {
    public let titleLabel = NSTextField(labelWithString: "")
    public let subtitleLabel = NSTextField(labelWithString: "")
    public let dayImageView = NSImageView()
    public let selectionBackground = NSView()
    public private(set) var dayState: DayState?
    private let dots = (0..<3).map { _ in NSView() }
    private var radius: CGFloat?
    public override func loadView() {
        view = CalendarDayView(frame: .zero); view.wantsLayer = true
        selectionBackground.wantsLayer = true
        view.addSubview(selectionBackground)
        for label in [titleLabel, subtitleLabel] {
            label.alignment = .center; label.isSelectable = false; label.setAccessibilityElement(false); view.addSubview(label)
        }
        dayImageView.imageScaling = .scaleProportionallyUpOrDown
        dayImageView.setAccessibilityElement(false); view.addSubview(dayImageView)
        for dot in dots { dot.wantsLayer = true; dot.layer?.cornerRadius = 2; view.addSubview(dot) }
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
    }
    open func apply(content: DayContent, state: DayState, appearance: FSCalendarAppearance, style: DayAppearance) {
        _ = view
        dayState = state; isSelected = state.isSelected; radius = style.cornerRadius
        view.isHidden = state.occurrence.isHidden
        titleLabel.stringValue = content.title ?? String(state.occurrence.day.day)
        subtitleLabel.stringValue = content.subtitle ?? ""
        titleLabel.font = appearance.titleFont; subtitleLabel.font = appearance.subtitleFont
        titleLabel.textColor = state.isSelected ? appearance.selectedTitleColor :
            (!state.occurrence.isSelectable ? appearance.disabledColor :
             (style.titleColor ?? (state.occurrence.position == .current ? appearance.titleColor : appearance.placeholderColor)))
        subtitleLabel.textColor = style.subtitleColor ?? appearance.subtitleColor
        dayImageView.image = content.image
        selectionBackground.layer?.backgroundColor = (state.isSelected ? (style.selectedFillColor ?? appearance.selectionColor) : (style.fillColor ?? .clear)).cgColor
        selectionBackground.layer?.borderColor = (style.borderColor ?? (state.isToday ? appearance.todayColor : .clear)).cgColor
        selectionBackground.layer?.borderWidth = style.borderColor != nil || state.isToday ? 1 : 0
        for (index, dot) in dots.enumerated() {
            dot.isHidden = index >= content.numberOfEvents
            dot.layer?.backgroundColor = (style.eventColor ?? appearance.eventColor).cgColor
        }
        view.setAccessibilityIdentifier("day.\(state.occurrence.day).\(state.occurrence.position.rawValue).\(state.occurrence.id.page.anchor)")
        view.setAccessibilityLabel(content.accessibilityLabel ?? state.occurrence.day.description)
        view.setAccessibilityValue(([content.accessibilityValue, state.isSelected ? "selected" : nil,
            state.isToday ? "today" : nil].compactMap { $0 }).joined(separator: ", "))
        view.setAccessibilityEnabled(state.occurrence.isSelectable)
        (view as? CalendarDayView)?.day = state.occurrence.day
        view.needsLayout = true
    }
    open override func viewDidLayout() {
        super.viewDidLayout()
        let size = view.bounds.size
        let titleHeight = titleLabel.intrinsicContentSize.height
        let subtitleHeight = subtitleLabel.stringValue.isEmpty ? 0 : subtitleLabel.intrinsicContentSize.height
        // Match the legacy cell: text and shape share the upper five-sixths.
        let contentHeight = size.height * 5 / 6
        let standardDiameter: CGFloat = 100 / 3
        let availableDiameter = max(0, min(size.width, contentHeight))
        let diameter = availableDiameter - max(0, availableDiameter - standardDiameter) / 2
        selectionBackground.frame = NSRect(x: (size.width - diameter) / 2, y: (contentHeight - diameter) / 2, width: diameter, height: diameter)
        selectionBackground.layer?.cornerRadius = radius ?? max(0, diameter / 2)
        let top = (contentHeight - titleHeight - subtitleHeight) / 2
        let imageWidth: CGFloat = dayImageView.image == nil ? 0 : 16
        titleLabel.frame = NSRect(x: 2, y: top, width: size.width - imageWidth - 4, height: titleHeight)
        dayImageView.frame = NSRect(x: size.width - 19, y: top + 1, width: imageWidth, height: 14)
        subtitleLabel.frame = NSRect(x: 2, y: top + titleHeight, width: size.width - 4, height: subtitleHeight)
        let eventSize = diameter / 6
        let dotHeight = min(4, eventSize * 0.83)
        let dotY = selectionBackground.frame.maxY + eventSize * 0.17 + (eventSize * 0.83 - dotHeight) / 2
        let count = dots.filter { !$0.isHidden }.count
        for (index, dot) in dots.enumerated() {
            dot.frame = NSRect(x: size.width / 2 - CGFloat(count * 7 - 3) / 2 + CGFloat(index * 7), y: dotY, width: 4, height: dotHeight)
            dot.layer?.cornerRadius = dotHeight / 2
        }
    }
    open override func prepareForReuse() {
        super.prepareForReuse(); dayState = nil; isSelected = false
        (view as? CalendarDayView)?.owner = nil; (view as? CalendarDayView)?.day = nil
        view.layer?.borderWidth = 0
        titleLabel.stringValue = ""; subtitleLabel.stringValue = ""; dayImageView.image = nil
        view.setAccessibilityLabel(nil); view.setAccessibilityValue(nil); view.setAccessibilityIdentifier(nil)
        selectionBackground.layer?.backgroundColor = nil; selectionBackground.layer?.borderWidth = 0
        for dot in dots { dot.isHidden = true }
    }
}
#endif
