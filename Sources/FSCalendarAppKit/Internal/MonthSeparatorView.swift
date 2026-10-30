#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

/// Separate decoration attributes keep month rules and fills independent of custom date cells.
@MainActor final class MonthSeparatorAttributes: NSCollectionViewLayoutAttributes {
    var path: CGPath?
    var lineWidth: CGFloat = 0
    var color: NSColor = .separatorColor

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

@MainActor final class MonthSeparatorView: NSView, NSCollectionViewElement {
    static let kind = "FSCalendar.monthSeparator"
    static let backgroundKind = "FSCalendar.monthBackground"
    private var path: CGPath?
    private var lineWidth: CGFloat = 0
    private var color: NSColor = .separatorColor

    override init(frame: CGRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        guard let attributes = layoutAttributes as? MonthSeparatorAttributes else { return }
        path = attributes.path; lineWidth = attributes.lineWidth; color = attributes.color; needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let path, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(path)
        if lineWidth > 0 {
            color.setStroke(); context.setLineWidth(lineWidth); context.strokePath()
        } else {
            color.setFill(); context.fillPath()
        }
    }
}
#endif
