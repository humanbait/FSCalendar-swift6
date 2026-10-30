#if canImport(UIKit)
import UIKit
import FSCalendarCore

@MainActor final class CalendarCollectionLayout: UICollectionViewLayout {
    var mode: CalendarDisplayMode = .month(.horizontal) { didSet { invalidateGeometry() } }
    var rows: [Int] = [] { didSet { invalidateGeometry() } }
    var rowHeight: CGFloat = 44 { didSet { invalidateGeometry() } }
    var continuousSections: [ContinuousMonthSection] = [] { didSet { invalidateGeometry() } }
    var isRTL = false { didSet { if oldValue != isRTL { invalidateGeometry() } } }
    var monthSeparatorColor: UIColor = .separator { didSet { invalidateLayout() } }
    var monthSeparatorCornerRadius: CGFloat = 8 { didSet { invalidateLayout() } }
    var monthBackgroundColor: UIColor = FSCalendarAppearance().backgroundColor { didSet { invalidateLayout() } }
    var alternatingMonthBackgroundColor: UIColor? = FSCalendarAppearance().alternatingMonthBackgroundColor { didSet { invalidateLayout() } }
    private var frames: [CGRect] = []
    private var size: CGSize = .zero
    private var preparedSize: CGSize = .zero
    private var geometryIsDirty = true

    override init() {
        super.init()
        register(MonthSeparatorView.self, forDecorationViewOfKind: MonthSeparatorView.kind)
        register(MonthSeparatorView.self, forDecorationViewOfKind: MonthSeparatorView.backgroundKind)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        register(MonthSeparatorView.self, forDecorationViewOfKind: MonthSeparatorView.kind)
        register(MonthSeparatorView.self, forDecorationViewOfKind: MonthSeparatorView.backgroundKind)
    }

    private func invalidateGeometry() { geometryIsDirty = true; invalidateLayout() }
    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let viewport = collectionView.bounds.size
        guard geometryIsDirty || viewport != preparedSize else { return }
        preparedSize = viewport; geometryIsDirty = false
        frames.removeAll(keepingCapacity: true)
        if mode.isContinuous {
            for section in continuousSections {
                frames.append(CGRect(x: 0, y: CGFloat(section.firstRow) * rowHeight,
                                     width: viewport.width, height: CGFloat(section.rowCount) * rowHeight))
            }
            // Allow the final month's first week to reach the viewport top even in a tall viewport.
            let bottom = frames.last.map { max($0.maxY, $0.minY + viewport.height) } ?? 0
            size = CGSize(width: viewport.width, height: bottom)
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
    override var collectionViewContentSize: CGSize { prepare(); return size }
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
                if frames[mid].minY <= offset.y + pixel * 0.5 { low = mid + 1 } else { high = mid }
            }
            return max(0, min(frames.count - 1, low - 1))
        }
        let length = mode.isHorizontal ? preparedSize.width : preparedSize.height
        guard length > 0 else { return 0 }
        let value = mode.isHorizontal ? offset.x : offset.y
        let visual = max(0, min(frames.count - 1, Int((value / length).rounded())))
        return mode.isHorizontal && isRTL ? frames.count - 1 - visual : visual
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        prepare()
        guard !frames.isEmpty else { return [] }
        let sections: [Int]
        if mode.isContinuous {
            var first = section(at: CGPoint(x: 0, y: rect.minY))
            // The preceding month may still own cells in this shared boundary row.
            if first > 0, frames[first - 1].maxY > rect.minY { first -= 1 }
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
            if mode.isContinuous, let background = layoutAttributesForDecorationView(ofKind: MonthSeparatorView.backgroundKind,
                at: IndexPath(item: 0, section: section)), background.frame.intersects(rect) {
                attributes.append(background)
            }
            for item in 0..<itemCount(in: section) {
                if let a = layoutAttributesForItem(at: IndexPath(item: item, section: section)), a.frame.intersects(rect) {
                    attributes.append(a)
                }
            }
        }
        if mode.isContinuous, frames.count > 1, let first = sections.min(), let last = sections.max() {
            // Include the next boundary when its pixel-aligned top touches this query.
            for section in max(1, first)...min(frames.count - 1, last + 1) {
                if let a = layoutAttributesForDecorationView(ofKind: MonthSeparatorView.kind,
                    at: IndexPath(item: 0, section: section)), a.frame.intersects(rect) {
                    attributes.append(a)
                }
            }
        }
        return attributes
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        prepare()
        guard frames.indices.contains(indexPath.section), indexPath.item >= 0,
              indexPath.item < itemCount(in: indexPath.section) else { return nil }
        let page = frames[indexPath.section]
        let width = page.width / 7
        let height = mode.isContinuous ? rowHeight : page.height / CGFloat(rows[indexPath.section])
        let slot = mode.isContinuous ? continuousSections[indexPath.section].startSlot + indexPath.item : indexPath.item
        let column = isRTL ? 6 - slot % 7 : slot % 7
        let attribute = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attribute.frame = CGRect(x: page.minX + CGFloat(column) * width,
                                 y: (mode.isContinuous ? 0 : page.minY) + CGFloat(slot / 7) * height,
                                 width: width, height: height)
        return attribute
    }
    override func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        prepare()
        let isBackground = elementKind == MonthSeparatorView.backgroundKind
        guard mode.isContinuous, preparedSize.width > 0, rowHeight > 0, indexPath.item == 0,
              isBackground || elementKind == MonthSeparatorView.kind,
              continuousSections.indices.contains(indexPath.section),
              isBackground || indexPath.section > 0 else { return nil }
        let section = continuousSections[indexPath.section]
        let scale = max(1, collectionView?.traitCollection.displayScale ?? 1)
        let width = (preparedSize.width * scale).rounded() / scale
        func boundary(_ slot: Int, internalBoundary: Bool) -> MonthBoundaryGeometry {
            MonthBoundaryGeometry(slot: slot, width: width, rowHeight: rowHeight, scale: scale,
                                  cornerRadius: monthSeparatorCornerRadius, internalBoundary: internalBoundary)
        }
        let top = boundary(section.startSlot, internalBoundary: indexPath.section > 0)
        let attributes = MonthSeparatorAttributes(forDecorationViewOfKind: elementKind, with: indexPath)
        let geometry: MonthDecorationGeometry
        if isBackground {
            let bottom = boundary(section.startSlot + section.dayCount,
                                  internalBoundary: indexPath.section + 1 < continuousSections.count)
            geometry = MonthDecorationGeometry(top: top, bottom: bottom, width: width, isRTL: isRTL)
            attributes.color = section.page.anchor.month.isMultiple(of: 2)
                ? (alternatingMonthBackgroundColor ?? monthBackgroundColor) : monthBackgroundColor
            attributes.zIndex = -1
        } else {
            geometry = MonthDecorationGeometry(boundary: top, width: width, scale: scale, isRTL: isRTL)
            attributes.lineWidth = 1 / scale
            attributes.color = monthSeparatorColor
            attributes.zIndex = 10
        }
        attributes.frame = geometry.frame; attributes.path = geometry.path
        return attributes
    }
    func itemCount(in section: Int) -> Int {
        if mode.isContinuous {
            return continuousSections.indices.contains(section) ? continuousSections[section].dayCount : 0
        }
        return rows.indices.contains(section) ? rows[section] * 7 : 0
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
