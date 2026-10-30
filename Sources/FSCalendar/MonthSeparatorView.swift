#if canImport(UIKit)
import UIKit

/// Separate decoration attributes keep month rules and fills independent of custom date cells.
@MainActor final class MonthSeparatorAttributes: UICollectionViewLayoutAttributes {
    var path: CGPath?
    var lineWidth: CGFloat = 0
    var color: UIColor = .separator

    override func copy(with zone: NSZone? = nil) -> Any {
        // Collection layouts copy and compare attributes on the UI thread.
        MainActor.assumeIsolated { () -> MonthSeparatorAttributes in
            let copy = super.copy(with: zone) as! MonthSeparatorAttributes
            copy.path = path; copy.lineWidth = lineWidth; copy.color = color
            return copy
        }
    }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MonthSeparatorAttributes else { return false }
        return MainActor.assumeIsolated {
            return path == other.path && lineWidth == other.lineWidth && color == other.color && super.isEqual(other)
        }
    }
}

@MainActor final class MonthSeparatorView: UICollectionReusableView {
    static let kind = "FSCalendar.monthSeparator"
    static let backgroundKind = "FSCalendar.monthBackground"
    private var path: CGPath?
    private var lineWidth: CGFloat = 0
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
        path = attributes.path; lineWidth = attributes.lineWidth; color = attributes.color; setNeedsDisplay()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let path, let context = UIGraphicsGetCurrentContext() else { return }
        context.addPath(path)
        if lineWidth > 0 {
            color.setStroke(); context.setLineWidth(lineWidth); context.strokePath()
        } else {
            color.setFill(); context.fillPath()
        }
    }
}
#endif
