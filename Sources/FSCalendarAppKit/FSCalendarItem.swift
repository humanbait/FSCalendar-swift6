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
        let size = view.bounds.size, titleHeight = (titleLabel.font?.pointSize ?? 15) + 4
        let subtitleHeight = (subtitleLabel.font?.pointSize ?? 10) + 3
        let diameter = min(size.width - 4, size.height - 4)
        selectionBackground.frame = NSRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
        selectionBackground.layer?.cornerRadius = radius ?? max(0, diameter / 2)
        let top = max(2, (size.height - titleHeight - (subtitleLabel.stringValue.isEmpty ? 0 : subtitleHeight) - 8) / 2)
        let imageWidth: CGFloat = dayImageView.image == nil ? 0 : 16
        titleLabel.frame = NSRect(x: 2, y: top, width: size.width - imageWidth - 4, height: titleHeight)
        dayImageView.frame = NSRect(x: size.width - 19, y: top + 1, width: imageWidth, height: 14)
        subtitleLabel.frame = NSRect(x: 2, y: top + titleHeight, width: size.width - 4, height: subtitleHeight)
        let count = dots.filter { !$0.isHidden }.count
        for (index, dot) in dots.enumerated() {
            dot.frame = NSRect(x: size.width / 2 - CGFloat(count * 7 - 3) / 2 + CGFloat(index * 7), y: size.height - 7, width: 4, height: 4)
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
