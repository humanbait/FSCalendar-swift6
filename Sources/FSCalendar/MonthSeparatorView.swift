#if canImport(UIKit)
import UIKit

/// Separate decoration attributes keep month rules independent of custom date cells.
@MainActor final class MonthSeparatorAttributes: UICollectionViewLayoutAttributes {
    var segments: [CGRect] = []
    var color: UIColor = .separator

    override func copy(with zone: NSZone? = nil) -> Any {
        // Collection layouts copy and compare attributes on the UI thread.
        MainActor.assumeIsolated { () -> MonthSeparatorAttributes in
            let copy = super.copy(with: zone) as! MonthSeparatorAttributes
            copy.segments = segments; copy.color = color
            return copy
        }
    }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MonthSeparatorAttributes else { return false }
        return MainActor.assumeIsolated {
            return segments == other.segments && color == other.color && super.isEqual(other)
        }
    }
}

@MainActor final class MonthSeparatorView: UICollectionReusableView {
    static let kind = "FSCalendar.monthSeparator"
    private var segments: [CGRect] = []
    private var color: UIColor = .separator

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; isUserInteractionEnabled = false; isAccessibilityElement = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        guard let attributes = layoutAttributes as? MonthSeparatorAttributes else { return }
        segments = attributes.segments; color = attributes.color; setNeedsDisplay()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        color.setFill()
        for segment in segments { UIRectFill(segment) }
    }
}
#endif
