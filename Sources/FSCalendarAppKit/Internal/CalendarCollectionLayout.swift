#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor final class CalendarCollectionLayout: NSCollectionViewLayout {
    var rows: [Int] = []
    var viewport: NSSize = .zero
    var isRTL = false
    override var collectionViewContentSize: NSSize {
        NSSize(width: viewport.width * CGFloat(rows.count), height: viewport.height)
    }
    func offset(for section: Int) -> NSPoint {
        NSPoint(x: CGFloat(isRTL ? rows.count - 1 - section : section) * viewport.width, y: 0)
    }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard viewport.width > 0, !rows.isEmpty else { return [] }
        let first = max(0, Int(floor(rect.minX / viewport.width)))
        let last = min(rows.count - 1, Int(floor(rect.maxX / viewport.width)))
        guard first <= last else { return [] }
        return (first...last).flatMap { visual -> [NSCollectionViewLayoutAttributes] in
            let section = isRTL ? rows.count - 1 - visual : visual
            return (0..<(rows[section] * 7)).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: section)) }
        }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard rows.indices.contains(indexPath.section), indexPath.item < rows[indexPath.section] * 7 else { return nil }
        let a = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        let column = isRTL ? 6 - indexPath.item % 7 : indexPath.item % 7
        let width = viewport.width / 7, height = viewport.height / CGFloat(rows[indexPath.section])
        a.frame = NSRect(x: offset(for: indexPath.section).x + CGFloat(column) * width,
                         y: CGFloat(indexPath.item / 7) * height, width: width, height: height)
        return a
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { false }
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: NSPoint) -> NSPoint { proposedContentOffset }
}
#endif
