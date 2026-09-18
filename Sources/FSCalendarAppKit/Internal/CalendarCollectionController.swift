#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor final class CalendarCollectionController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    weak var owner: FSCalendarView?
    var cache: [PageID: CalendarGrid] = [:]
    var recency: [PageID] = []
    var registered: Set<String> = ["default"]
    func grid(_ section: Int) -> CalendarGrid? {
        guard let owner, let id = try? owner.engine.page(at: section, scope: owner.displayMode.scope) else { return nil }
        recency.removeAll { $0 == id }; recency.append(id)
        if let grid = cache[id] { return grid }
        guard let grid = try? owner.engine.grid(containing: id.anchor, scope: id.scope) else { return nil }
        cache[id] = grid
        while recency.count > 9 { cache.removeValue(forKey: recency.removeFirst()) }
        return grid
    }
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> { [] }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("month"), for: indexPath)
        if let header = view as? CalendarMonthHeader, let owner, let page = try? owner.engine.page(at: indexPath.section, scope: .month) {
            header.label.stringValue = (try? page.anchor.date(in: owner.configuration.timeZone)).map { owner.formatter("LLLL yyyy").string(from: $0) } ?? page.anchor.description
            header.label.font = owner.metrics.headerFont; header.label.textColor = owner.metrics.headerColor
            header.wantsLayer = true; header.layer?.backgroundColor = owner.metrics.backgroundColor.cgColor
            header.setAccessibilityIdentifier("month.\(page.anchor)")
        }
        return view
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { owner?.calendarLayout.rows.count ?? 0 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let rows = owner?.calendarLayout.rows, rows.indices.contains(section) else { return 0 }
        return rows[section] * 7
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("default"), for: indexPath)
        if let item = item as? FSCalendarItem, let grid = grid(indexPath.section), grid.occurrences.indices.contains(indexPath.item) {
            owner?.configure(item, occurrence: grid.occurrences[indexPath.item])
        }
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        if let item = item as? FSCalendarItem, let grid = grid(indexPath.section), grid.occurrences.indices.contains(indexPath.item) {
            owner?.configure(item, occurrence: grid.occurrences[indexPath.item])
        }
    }
}
@MainActor final class CalendarMonthHeader: NSView, NSCollectionViewElement {
    let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) { super.init(frame: frame); addSubview(label); label.alignment = .center }
    required init?(coder: NSCoder) { super.init(coder: coder); addSubview(label) }
    override func layout() { super.layout(); label.frame = bounds.insetBy(dx: 0, dy: 8) }
}
#endif
