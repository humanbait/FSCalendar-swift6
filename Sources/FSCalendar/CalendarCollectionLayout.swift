#if canImport(UIKit)
import UIKit

@MainActor final class CalendarCollectionLayout: UICollectionViewLayout {
    var mode: CalendarDisplayMode = .month(.horizontal) { didSet { invalidateGeometry() } }
    var rows: [Int] = [] { didSet { invalidateGeometry() } }
    var rowHeight: CGFloat = 44 { didSet { invalidateGeometry() } }
    var headerHeight: CGFloat = 44 { didSet { invalidateGeometry() } }
    var isRTL = false { didSet { if oldValue != isRTL { invalidateGeometry() } } }
    private var frames: [CGRect] = []
    private var size: CGSize = .zero
    private var preparedSize: CGSize = .zero
    private var geometryIsDirty = true

    private func invalidateGeometry() { geometryIsDirty = true; invalidateLayout() }
    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let viewport = collectionView.bounds.size
        guard geometryIsDirty || viewport != preparedSize else { return }
        preparedSize = viewport; geometryIsDirty = false
        frames.removeAll(keepingCapacity: true)
        if mode.isContinuous {
            var top: CGFloat = 0
            for count in rows {
                let scale = max(1, collectionView.traitCollection.displayScale)
                let height = ceil((headerHeight + CGFloat(count) * rowHeight) * scale) / scale
                frames.append(CGRect(x: 0, y: top, width: viewport.width, height: height))
                top += height
            }
            size = CGSize(width: viewport.width, height: top)
        } else {
            for index in rows.indices {
                let visual = mode.isHorizontal && isRTL ? rows.count - 1 - index : index
                frames.append(CGRect(x: mode.isHorizontal ? CGFloat(visual) * viewport.width : 0,
                                     y: mode.isHorizontal ? 0 : CGFloat(visual) * viewport.height,
                                     width: viewport.width, height: viewport.height))
            }
            size = CGSize(width: viewport.width * CGFloat(mode.isHorizontal ? rows.count : 1),
                          height: viewport.height * CGFloat(mode.isHorizontal ? 1 : rows.count))
        }
    }
    override var collectionViewContentSize: CGSize { size }
    func offset(for section: Int) -> CGPoint {
        prepare()
        return frames.indices.contains(section) ? frames[section].origin : .zero
    }
    func section(at offset: CGPoint) -> Int {
        prepare()
        guard !frames.isEmpty else { return 0 }
        if mode.isContinuous {
            var low = 0, high = frames.count
            while low < high {
                let mid = (low + high) / 2
                let pixel = 1 / max(1, collectionView?.traitCollection.displayScale ?? 1)
                if frames[mid].maxY <= offset.y + pixel * 0.5 { low = mid + 1 } else { high = mid }
            }
            return min(frames.count - 1, low)
        }
        let length = mode.isHorizontal ? preparedSize.width : preparedSize.height
        guard length > 0 else { return 0 }
        let value = mode.isHorizontal ? offset.x : offset.y
        let visual = max(0, min(frames.count - 1, Int((value / length).rounded())))
        return mode.isHorizontal && isRTL ? frames.count - 1 - visual : visual
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !frames.isEmpty else { return [] }
        let sections: [Int]
        if mode.isContinuous {
            let first = section(at: CGPoint(x: 0, y: rect.minY))
            var last = first
            while last + 1 < frames.count && frames[last + 1].minY < rect.maxY { last += 1 }
            sections = Array(first...last)
        } else {
            let extent = mode.isHorizontal ? preparedSize.width : preparedSize.height
            guard extent > 0 else { return [] }
            let first = max(0, Int(floor((mode.isHorizontal ? rect.minX : rect.minY) / extent)))
            let last = min(frames.count - 1, Int(floor((mode.isHorizontal ? rect.maxX : rect.maxY) / extent)))
            guard first <= last else { return [] }
            sections = (first...last).map { mode.isHorizontal && isRTL ? frames.count - 1 - $0 : $0 }
        }
        var attributes: [UICollectionViewLayoutAttributes] = []
        for section in sections {
            for item in 0..<(rows[section] * 7) {
                if let a = layoutAttributesForItem(at: IndexPath(item: item, section: section)), a.frame.intersects(rect) {
                    attributes.append(a)
                }
            }
            if mode.isContinuous, let header = layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader,
                                                                                     at: IndexPath(item: 0, section: section)) {
                attributes.append(header)
            }
        }
        return attributes
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.section), indexPath.item < rows[indexPath.section] * 7 else { return nil }
        let page = frames[indexPath.section]
        let width = page.width / 7
        let height = mode.isContinuous ? rowHeight : page.height / CGFloat(rows[indexPath.section])
        let column = isRTL ? 6 - indexPath.item % 7 : indexPath.item % 7
        let attribute = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attribute.frame = CGRect(x: page.minX + CGFloat(column) * width,
                                 y: page.minY + (mode.isContinuous ? headerHeight : 0) + CGFloat(indexPath.item / 7) * height,
                                 width: width, height: height)
        return attribute
    }
    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard mode.isContinuous, elementKind == UICollectionView.elementKindSectionHeader,
              frames.indices.contains(indexPath.section) else { return nil }
        let page = frames[indexPath.section]
        let attribute = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: elementKind, with: indexPath)
        let top = min(page.maxY - headerHeight, max(page.minY, collectionView?.contentOffset.y ?? 0))
        attribute.frame = CGRect(x: 0, y: top, width: page.width, height: headerHeight)
        attribute.zIndex = 100
        return attribute
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        mode.isContinuous || newBounds.size != preparedSize
    }
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint,
                                     withScrollingVelocity velocity: CGPoint) -> CGPoint {
        mode.isContinuous ? proposedContentOffset : offset(for: section(at: proposedContentOffset))
    }
}
#endif
