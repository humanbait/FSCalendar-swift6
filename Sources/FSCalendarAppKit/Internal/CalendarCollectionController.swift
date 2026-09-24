#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor final class CalendarCollectionController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    weak var owner: FSCalendarView?
    var cache: [PageID: CalendarGrid] = [:]
    var recency: [PageID] = []
    var registered: Set<String> = ["default"]
    func grid(_ section: Int) -> CalendarGrid? {
        guard let owner, let id = try? owner.engine.page(at: section, scope: owner.renderingMode.scope) else { return nil }
        recency.removeAll { $0 == id }; recency.append(id)
        if let grid = cache[id] { return grid }
        guard let grid = try? owner.renderingMode.isContinuous
            ? owner.engine.continuousMonthGrid(containing: id.anchor)
            : owner.engine.grid(containing: id.anchor, scope: id.scope) else { return nil }
        cache[id] = grid
        while recency.count > 9 { cache.removeValue(forKey: recency.removeFirst()) }
        return grid
    }
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> { [] }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { owner?.calendarLayout.rows.count ?? 0 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        owner?.calendarLayout.itemCount(in: section) ?? 0
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let occurrence = grid(indexPath.section)?.occurrences[indexPath.item]
        let requested = occurrence.flatMap { day in owner.flatMap { $0.dataSource?.calendar($0, reuseIdentifierFor: day.day) } } ?? "default"
        let identifier = registered.contains(requested) ? requested : "default"
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(identifier), for: indexPath)
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
#endif
