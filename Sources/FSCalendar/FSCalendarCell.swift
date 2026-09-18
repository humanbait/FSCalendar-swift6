#if canImport(UIKit)
import UIKit
import FSCalendarCore

/// Subclass and override `apply` or `layoutSubviews` for custom shapes and content.
@MainActor open class FSCalendarCell: UICollectionViewCell {
    public let titleLabel = UILabel()
    public let subtitleLabel = UILabel()
    public let dayImageView = UIImageView()
    public let selectionBackground = UIView()
    public private(set) var dayState: DayState?
    private let eventStack = UIStackView()
    private var radius: CGFloat?

    public override init(frame: CGRect) { super.init(frame: frame); setUp() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setUp() }
    private func setUp() {
        contentView.addSubview(selectionBackground)
        [titleLabel, subtitleLabel].forEach {
            $0.textAlignment = .center; $0.adjustsFontForContentSizeCategory = true
            $0.adjustsFontSizeToFitWidth = true; $0.minimumScaleFactor = 0.65
            contentView.addSubview($0)
        }
        dayImageView.contentMode = .scaleAspectFit
        contentView.addSubview(dayImageView)
        eventStack.axis = .horizontal; eventStack.spacing = 3; eventStack.distribution = .fillEqually
        contentView.addSubview(eventStack)
        for _ in 0..<3 {
            let dot = UIView(); dot.layer.cornerRadius = 2
            eventStack.addArrangedSubview(dot)
        }
        isAccessibilityElement = true
    }
    open func apply(content: DayContent, state: DayState, appearance: FSCalendarAppearance, style: DayAppearance) {
        dayState = state
        isHidden = state.occurrence.isHidden
        isSelected = state.isSelected
        titleLabel.font = appearance.titleFont
        subtitleLabel.font = appearance.subtitleFont
        titleLabel.text = content.title ?? String(state.occurrence.day.day)
        subtitleLabel.text = content.subtitle
        dayImageView.image = content.image
        dayImageView.tintColor = style.titleColor ?? appearance.titleColor
        radius = style.cornerRadius.flatMap { $0.isFinite ? max(0, $0) : nil }
        let normalColor = state.occurrence.isSelectable ? (state.occurrence.position == .current ? appearance.titleColor : appearance.placeholderColor) : appearance.disabledColor
        titleLabel.textColor = state.isSelected ? appearance.selectedTitleColor : (style.titleColor ?? normalColor)
        subtitleLabel.textColor = state.isSelected ? appearance.selectedTitleColor : (style.subtitleColor ?? appearance.subtitleColor)
        selectionBackground.backgroundColor = state.isSelected ? (style.selectedFillColor ?? appearance.selectionColor)
            : (style.fillColor ?? (state.isToday ? appearance.todayColor.withAlphaComponent(0.18) : .clear))
        selectionBackground.layer.borderColor = (style.borderColor ?? (state.isToday ? appearance.todayColor : .clear)).cgColor
        selectionBackground.layer.borderWidth = style.borderColor != nil || state.isToday ? 1 : 0
        for (index, dot) in eventStack.arrangedSubviews.enumerated() {
            dot.isHidden = index >= min(3, content.numberOfEvents)
            dot.backgroundColor = state.isSelected ? appearance.selectedTitleColor : (style.eventColor ?? appearance.eventColor)
        }
        eventStack.isHidden = content.numberOfEvents == 0
        accessibilityTraits = state.isSelected ? [.button, .selected] : [.button]
        if !state.occurrence.isSelectable { accessibilityTraits.insert(.notEnabled) }
        accessibilityIdentifier = "day.\(state.occurrence.day).\(state.occurrence.position.rawValue).\(state.occurrence.id.page.anchor)"
        accessibilityValue = content.accessibilityValue ?? [content.subtitle, content.numberOfEvents > 0 ? "\(content.numberOfEvents) events" : nil,
                              state.isToday ? "Today" : nil].compactMap { $0 }.joined(separator: ", ")
        setNeedsLayout()
    }
    open override func layoutSubviews() {
        super.layoutSubviews()
        let hasSubtitle = !(subtitleLabel.text ?? "").isEmpty
        let hasImage = dayImageView.image != nil
        let textHeight = min(titleLabel.font.lineHeight, bounds.height * (hasSubtitle || hasImage ? 0.45 : 0.7))
        let subtitleHeight = hasSubtitle ? min(subtitleLabel.font.lineHeight, bounds.height * 0.25) : 0
        // Match the legacy cell: text and shape share the upper five-sixths.
        let contentHeight = bounds.height * 5 / 6
        let top = (contentHeight - textHeight - subtitleHeight) / 2
        let imageSpace: CGFloat = hasImage ? 16 : 0
        let imageOnLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        titleLabel.frame = CGRect(x: 2 + (imageOnLeft ? imageSpace : 0), y: top,
                                  width: max(0, bounds.width - 4 - imageSpace), height: textHeight)
        subtitleLabel.frame = CGRect(x: 1, y: titleLabel.frame.maxY, width: bounds.width - 2, height: subtitleHeight)
        dayImageView.frame = CGRect(x: imageOnLeft ? 2 : bounds.width - 14, y: top + max(0, (textHeight - 12) / 2),
                                    width: 12, height: hasImage ? min(12, textHeight) : 0)
        let dotCount = eventStack.arrangedSubviews.filter { !$0.isHidden }.count
        let dotWidth = CGFloat(max(0, dotCount * 7 - 3))
        let standardDiameter: CGFloat = 100 / 3
        let availableDiameter = max(0, min(bounds.width, contentHeight))
        let side = availableDiameter - max(0, availableDiameter - standardDiameter) / 2
        selectionBackground.frame = CGRect(x: (bounds.width - side) / 2, y: (contentHeight - side) / 2, width: side, height: side)
        let eventSize = side / 6
        let dotHeight = min(4, eventSize * 0.83)
        let dotY = selectionBackground.frame.maxY + eventSize * 0.17 + (eventSize * 0.83 - dotHeight) / 2
        eventStack.frame = CGRect(x: (bounds.width - dotWidth) / 2, y: dotY, width: dotWidth, height: dotHeight)
        for dot in eventStack.arrangedSubviews { dot.layer.cornerRadius = dotHeight / 2 }
        selectionBackground.layer.cornerRadius = radius ?? min(selectionBackground.bounds.width, selectionBackground.bounds.height) / 2
    }
    open override func prepareForReuse() {
        super.prepareForReuse()
        dayState = nil; titleLabel.text = nil; subtitleLabel.text = nil; dayImageView.image = nil
        accessibilityLabel = nil; accessibilityValue = nil; accessibilityIdentifier = nil
        isHidden = false; isSelected = false
    }
}

@MainActor final class CalendarMonthHeader: UICollectionReusableView {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center; label.adjustsFontForContentSizeCategory = true
        label.accessibilityTraits = .header; addSubview(label)
    }
    required init?(coder: NSCoder) { super.init(coder: coder); addSubview(label) }
    override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds.insetBy(dx: 8, dy: 2) }
}
#endif
