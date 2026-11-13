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
    var continuousCenteringProgress: CGFloat = 0 {
        didSet { if oldValue != continuousCenteringProgress { view.needsLayout = true } }
    }
    var hasAutomaticYearSubtitle = false
    private var originalTitleFont: NSFont?
    private var originalSubtitleFont: NSFont?
    private var normalEventColor: NSColor = .clear
    private var selectedEventColor: NSColor = .clear
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
        originalTitleFont = nil; originalSubtitleFont = nil
        subtitleLabel.alphaValue = hasAutomaticYearSubtitle ? continuousCenteringProgress : 1
        normalEventColor = style.eventColor ?? appearance.eventColor
        selectedEventColor = appearance.selectedTitleColor
        titleLabel.textColor = state.isSelected ? appearance.selectedTitleColor :
            (!state.occurrence.isSelectable ? appearance.disabledColor :
             (style.titleColor ?? (state.occurrence.position == .current ? appearance.titleColor : appearance.placeholderColor)))
        subtitleLabel.textColor = hasAutomaticYearSubtitle && state.isSelected
            ? appearance.selectedTitleColor : (style.subtitleColor ?? appearance.subtitleColor)
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
        let imageWidth: CGFloat = dayImageView.image == nil ? 0 : 16
        let count = dots.filter { !$0.isHidden }.count
        let dotWidth = CGFloat(max(0, count * 7 - 3))
        let inlineSpace = hasAutomaticYearSubtitle && count > 0 ? dotWidth + 3 : 0
        if hasAutomaticYearSubtitle {
            originalTitleFont = originalTitleFont ?? titleLabel.font
            originalSubtitleFont = originalSubtitleFont ?? subtitleLabel.font
            func fitted(_ label: NSTextField, original: NSFont?, width: CGFloat, height: CGFloat) -> NSFont? {
                guard let original else { return nil }
                let measured = (label.stringValue as NSString).size(withAttributes: [.font: original])
                let scale = min(1, max(0.01, width - 4) / max(1, measured.width), max(0.01, height - 2) / max(1, measured.height))
                return NSFont(descriptor: original.fontDescriptor, size: original.pointSize * scale)
            }
            titleLabel.font = fitted(titleLabel, original: originalTitleFont, width: size.width - imageWidth - 4, height: size.height * 0.45)
            subtitleLabel.font = fitted(subtitleLabel, original: originalSubtitleFont, width: size.width - 4 - inlineSpace, height: size.height * 0.25)
        }
        let subtitleProgress = hasAutomaticYearSubtitle ? continuousCenteringProgress : 1
        subtitleLabel.alphaValue = subtitleProgress
        let hasSubtitle = !subtitleLabel.stringValue.isEmpty
        let naturalTitleHeight = titleLabel.intrinsicContentSize.height
        let naturalSubtitleHeight = hasSubtitle ? subtitleLabel.intrinsicContentSize.height : 0
        let titleLimit = size.height * (hasSubtitle || imageWidth > 0 ? 0.45 : 0.7)
        let titleHeight = naturalTitleHeight + (min(naturalTitleHeight, titleLimit) - naturalTitleHeight) * continuousCenteringProgress
        let subtitleHeight = naturalSubtitleHeight + (min(naturalSubtitleHeight, size.height * 0.25) - naturalSubtitleHeight) * continuousCenteringProgress
        let occupiedSubtitleHeight = subtitleHeight * subtitleProgress
        // Keep the legacy circle size while centering continuous content.
        let contentHeight = size.height * 5 / 6
        let offset = size.height / 12 * continuousCenteringProgress
        let standardDiameter: CGFloat = 100 / 3
        let availableDiameter = max(0, min(size.width, contentHeight))
        let diameter = availableDiameter - max(0, availableDiameter - standardDiameter) / 2
        selectionBackground.frame = NSRect(x: (size.width - diameter) / 2, y: (contentHeight - diameter) / 2 + offset, width: diameter, height: diameter)
        selectionBackground.layer?.cornerRadius = radius ?? max(0, diameter / 2)
        let top = (contentHeight - titleHeight - occupiedSubtitleHeight) / 2 + offset
        titleLabel.frame = NSRect(x: 2, y: top, width: size.width - imageWidth - 4, height: titleHeight)
        let imageY = top + 1 + ((titleHeight - 14) / 2 - 1) * continuousCenteringProgress
        dayImageView.frame = NSRect(x: size.width - 19, y: imageY, width: imageWidth, height: 14)
        subtitleLabel.frame = NSRect(x: 2, y: top + titleHeight, width: size.width - 4, height: subtitleHeight)
        let eventSize = diameter / 6
        let dotHeight = min(4, eventSize * 0.83)
        let legacyDotY = (contentHeight + diameter) / 2 + eventSize * 0.17 + (eventSize * 0.83 - dotHeight) / 2
        let centeredDotY = min(max(0, size.height - dotHeight), (size.height + titleHeight + occupiedSubtitleHeight) / 2 + 2)
        let dotY = legacyDotY + (centeredDotY - legacyDotY) * continuousCenteringProgress
        var inlineX = size.width / 2 - dotWidth / 2
        if hasAutomaticYearSubtitle, count > 0 {
            let yearWidth = min(subtitleLabel.intrinsicContentSize.width, max(0, size.width - 4 - inlineSpace))
            let rtl = view.userInterfaceLayoutDirection == .rightToLeft
            let groupX = max(2, min(size.width / 2 - yearWidth / 2 - (rtl ? inlineSpace : 0), size.width - 2 - yearWidth - inlineSpace))
            subtitleLabel.frame.origin.x = groupX + (rtl ? inlineSpace : 0)
            subtitleLabel.frame.size.width = yearWidth
            inlineX = rtl ? groupX : subtitleLabel.frame.maxX + 3
        }
        for (index, dot) in dots.enumerated() {
            dot.frame = NSRect(x: size.width / 2 - CGFloat(count * 7 - 3) / 2 + CGFloat(index * 7), y: dotY, width: 4, height: dotHeight)
            if hasAutomaticYearSubtitle, count > 0 {
                let targetX = inlineX + CGFloat(index * 7)
                let targetY = subtitleLabel.frame.midY - dotHeight / 2
                dot.frame.origin.x += (targetX - dot.frame.minX) * continuousCenteringProgress
                dot.frame.origin.y += (targetY - dot.frame.minY) * continuousCenteringProgress
            }
            dot.layer?.cornerRadius = dotHeight / 2
            let shape = NSBezierPath(roundedRect: selectionBackground.frame, xRadius: radius ?? diameter / 2, yRadius: radius ?? diameter / 2)
            let insideSelection = continuousCenteringProgress > 0 &&
                [CGPoint(x: dot.frame.minX, y: dot.frame.minY), CGPoint(x: dot.frame.maxX, y: dot.frame.minY),
                 CGPoint(x: dot.frame.minX, y: dot.frame.maxY), CGPoint(x: dot.frame.maxX, y: dot.frame.maxY)].allSatisfy(shape.contains)
            dot.layer?.backgroundColor = (isSelected && insideSelection ? selectedEventColor : normalEventColor).cgColor
        }
    }
    open override func prepareForReuse() {
        super.prepareForReuse(); dayState = nil; isSelected = false
        continuousCenteringProgress = 0; hasAutomaticYearSubtitle = false
        originalTitleFont = nil; originalSubtitleFont = nil; subtitleLabel.alphaValue = 1
        (view as? CalendarDayView)?.owner = nil; (view as? CalendarDayView)?.day = nil
        view.layer?.borderWidth = 0
        titleLabel.stringValue = ""; subtitleLabel.stringValue = ""; dayImageView.image = nil
        view.setAccessibilityLabel(nil); view.setAccessibilityValue(nil); view.setAccessibilityIdentifier(nil)
        selectionBackground.layer?.backgroundColor = nil; selectionBackground.layer?.borderWidth = 0
        for dot in dots { dot.isHidden = true }
    }
}
#endif
