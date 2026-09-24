#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

/// Separate decoration attributes keep month rules independent of custom date cells.
@MainActor final class MonthSeparatorAttributes: NSCollectionViewLayoutAttributes {
    var segments: [CGRect] = []
    var color: NSColor = .separatorColor

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

@MainActor final class MonthSeparatorView: NSView, NSCollectionViewElement {
    static let kind = "FSCalendar.monthSeparator"
    private var segments: [CGRect] = []
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
        segments = attributes.segments; color = attributes.color; needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        for segment in segments { segment.fill() }
    }
}
#endif
