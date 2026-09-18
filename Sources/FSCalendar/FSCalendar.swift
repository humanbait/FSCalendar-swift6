#if canImport(UIKit)
import UIKit
import FSCalendarCore

/// A UIKit calendar. All view, provider, delegate, and mutation APIs are main-actor isolated.
@MainActor public final class FSCalendar: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    public weak var delegate: (any FSCalendarDelegate)? {
        didSet {
            if oldValue !== delegate { lastDeliveredHeight = nil }
        }
    }
    private var lastDeliveredHeight: CGFloat?
    public weak var dataSource: (any FSCalendarDataSource)? { didSet { reloadData() } }
    public var appearance = FSCalendarAppearance() { didSet { refreshAppearance() } }
    var resolvedAppearance = FSCalendarAppearance()
    var reduceMotionOverride: Bool?
    var reduceMotion: Bool { reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled }
    public var today: CivilDay? { didSet { reload(dates: Set([oldValue, today].compactMap { $0 })) } }
    public var swipeSelectionEnabled = false { didSet { selectionGesture.isEnabled = swipeSelectionEnabled } }
    public var scopeGestureEnabled = true { didSet { updateGestureAvailability() } }
    public var configuration: CalendarConfiguration { engine.configuration }
    public var selectedDays: [CivilDay] { selection.days }
    public var selectedDate: Date? { selection.latest.flatMap { try? $0.date(in: configuration.timeZone) } }
    public var selectedDates: [Date] { selection.days.compactMap { try? $0.date(in: configuration.timeZone) } }
    public var currentPage: CivilDay { page }
    public var displayMode: CalendarDisplayMode { mode }
    public var transitionState: CalendarTransitionState { transitionPhase }
    public var preferredHeight: CGFloat {
        if let transition { return transition.sourceHeight + (transition.targetHeight - transition.sourceHeight) * transition.progress }
        return height(for: mode, page: page)
    }
    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: mode.isContinuous ? UIView.noIntrinsicMetric : preferredHeight)
    }
    public override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: preferredHeight) }

    var engine = try! CalendarEngine(configuration: CalendarConfiguration())
    var selection = SelectionState()
    var page = try! CivilDay(year: 1970, month: 1, day: 1)
    var mode: CalendarDisplayMode = .month(.horizontal)
    var renderingMode: CalendarDisplayMode = .month(.horizontal)
    var lastMonthAxis: CalendarScrollAxis = .horizontal
    var transitionPhase: CalendarTransitionState = .idle
    var transition: CalendarTransition?
    var isMutating = false
    var isLayingOut = false
    var needsPagePosition = true
    var lastBoundsSize = CGSize.zero
    let calendarLayout = CalendarCollectionLayout()
    lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: calendarLayout)
    let clipView = UIView()
    let titleLabel = UILabel()
    let weekdayStack = UIStackView()
    var gridCache: [PageID: CalendarGrid] = [:]
    var cacheOrder: [PageID] = []
    var cachedPageCount: Int { gridCache.count }
    var registeredIdentifiers: Set<String> = ["default"]
    let monthFormatter = DateFormatter()
    let accessibilityFormatter = DateFormatter()
    lazy var scopeGesture = UIPanGestureRecognizer(target: self, action: #selector(scopePan(_:)))
    lazy var selectionGesture = UILongPressGestureRecognizer(target: self, action: #selector(selectionPan(_:)))
    var swipeVisited: Set<CivilDay> = []
    var swipeRemoves = false

    public override init(frame: CGRect) { super.init(frame: frame); setUp() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setUp() }
    private func setUp() {
        today = try? CivilDay(date: Date(), timeZone: configuration.timeZone)
        page = engine.pageID(containing: clamped(today ?? configuration.minimumDate), scope: .month).anchor
        titleLabel.textAlignment = .center; titleLabel.accessibilityTraits = .header
        titleLabel.adjustsFontForContentSizeCategory = true
        weekdayStack.axis = .horizontal; weekdayStack.distribution = .fillEqually
        weekdayStack.semanticContentAttribute = .forceLeftToRight // Order is assigned explicitly with the grid columns.
        for _ in 0..<7 { let label = UILabel(); label.textAlignment = .center; label.adjustsFontForContentSizeCategory = true; weekdayStack.addArrangedSubview(label) }
        addSubview(titleLabel); addSubview(weekdayStack); addSubview(clipView)
        clipView.clipsToBounds = true; clipView.addSubview(collectionView)
        collectionView.dataSource = self; collectionView.delegate = self
        collectionView.accessibilityIdentifier = "calendar-grid"
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = true // The transaction model enforces the configured selection mode.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsHorizontalScrollIndicator = false; collectionView.showsVerticalScrollIndicator = false
        collectionView.register(FSCalendarCell.self, forCellWithReuseIdentifier: "default")
        collectionView.register(CalendarMonthHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "month")
        scopeGesture.delegate = self; clipView.addGestureRecognizer(scopeGesture)
        selectionGesture.minimumPressDuration = 0.25; selectionGesture.isEnabled = false
        collectionView.addGestureRecognizer(selectionGesture)
        NotificationCenter.default.addObserver(self, selector: #selector(clockDidChange), name: UIApplication.significantTimeChangeNotification, object: nil)
        refreshAppearance()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    public func apply(configuration: CalendarConfiguration) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        let replacement = try CalendarEngine(configuration: configuration)
        cancelTransition()
        isMutating = true; defer { isMutating = false }
        let previousPage = page
        let change = selection.pruningChange(for: replacement)
        engine = replacement
        if let change { selection.commit(change) }
        page = engine.pageID(containing: clamped(page), scope: mode.scope).anchor
        refreshAppearance()
        if let change { delegate?.calendar(self, didChangeSelection: change) }
        if page != previousPage { delegate?.calendarCurrentPageDidChange(self) }
    }
    public func setCurrentPage(_ day: CivilDay, animated: Bool = false) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        let section = try engine.sectionIndex(for: day, scope: mode.scope)
        cancelTransition()
        layoutIfNeeded()
        let previousHeight = preferredHeight
        let next = try engine.page(at: section, scope: mode.scope).anchor
        let changed = page != next
        page = next; needsPagePosition = false
        updateHeader(); updatePageHeight(from: previousHeight, animated: animated)
        collectionView.setContentOffset(calendarLayout.offset(for: section), animated: animated && !reduceMotion)
        if changed { delegate?.calendarCurrentPageDidChange(self) }
    }
    public func setCurrentPage(_ date: Date, animated: Bool = false) throws {
        try setCurrentPage(CivilDay(date: date, timeZone: configuration.timeZone), animated: animated)
    }
    public func navigate(_ offset: Int, animated: Bool = true) throws {
        let current = try engine.sectionIndex(for: page, scope: mode.scope)
        let (index, overflow) = current.addingReportingOverflow(offset)
        guard !overflow else { throw CalendarError.invalidPageIndex(offset) }
        try setCurrentPage(engine.page(at: index, scope: mode.scope).anchor, animated: animated)
    }
    public func select(_ day: CivilDay) throws {
        let proposed = configuration.selectionMode == .multiple ? selectedDays + [day] : [day]
        try setSelection(proposed)
    }
    public func select(_ date: Date) throws { try select(CivilDay(date: date, timeZone: configuration.timeZone)) }
    public func deselect(_ day: CivilDay) throws { try setSelection(selectedDays.filter { $0 != day }) }
    public func clearSelection() throws { try setSelection([]) }
    public func setSelection(_ days: [CivilDay]) throws { try transact(days, origin: .programmatic) }
    func transact(_ days: [CivilDay], origin: SelectionOrigin) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        isMutating = true; defer { isMutating = false }
        guard let change = try selection.propose(days, engine: engine, origin: origin) else { return }
        guard delegate?.calendar(self, shouldApply: change) ?? true else { throw CalendarError.selectionVetoed }
        selection.commit(change)
        reload(dates: Set(change.added + change.removed))
        let added = Set(change.added)
        for case let cell as FSCalendarCell in collectionView.visibleCells {
            if let day = cell.dayState?.occurrence.day, added.contains(day) {
                cell.animateSelection(reduceMotion: reduceMotion)
            }
        }
        delegate?.calendar(self, didChangeSelection: change)
    }
    public func register(_ cellClass: FSCalendarCell.Type, forCellReuseIdentifier identifier: String) throws {
        guard !identifier.isEmpty else { throw CalendarError.invalidConfiguration("Cell reuse identifier must not be empty") }
        registeredIdentifiers.insert(identifier)
        collectionView.register(cellClass, forCellWithReuseIdentifier: identifier)
    }
    public func reloadData() {
        guard collectionView.dataSource != nil else { return }
        gridCache.removeAll(keepingCapacity: true); cacheOrder.removeAll(keepingCapacity: true)
        for index in collectionView.indexPathsForSelectedItems ?? [] { collectionView.deselectItem(at: index, animated: false) }
        collectionView.reloadData(); needsPagePosition = true; setNeedsLayout()
    }
    public func reload(dates: Set<CivilDay>) {
        for case let cell as FSCalendarCell in collectionView.visibleCells {
            if let occurrence = cell.dayState?.occurrence, dates.contains(occurrence.day) {
                configure(cell, occurrence: occurrence)
                if let index = collectionView.indexPath(for: cell) { synchronizeSelection(at: index, day: occurrence.day) }
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !isLayingOut else { return }
        isLayingOut = true; defer { isLayingOut = false }
        if transition != nil && lastBoundsSize != .zero &&
            (abs(bounds.width - lastBoundsSize.width) > 0.5 ||
             (abs(bounds.height - lastBoundsSize.height) > 0.5 && abs(bounds.height - preferredHeight) > 1)) {
            cancelTransition()
        }
        let needsRepositionForSize = bounds.width != lastBoundsSize.width ||
            (bounds.height != lastBoundsSize.height && !renderingMode.isHorizontal)
        lastBoundsSize = bounds.size
        let headerHeight = renderingMode.isContinuous ? 0 : effectiveHeaderHeight
        titleLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        weekdayStack.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: effectiveWeekdayHeight)
        let top = headerHeight + effectiveWeekdayHeight
        let available = max(0, bounds.height - top)
        clipView.frame = CGRect(x: 0, y: top, width: bounds.width, height: available)
        let gridHeight = transition?.renderGridHeight ?? available
        collectionView.bounds.size = CGSize(width: bounds.width, height: gridHeight)
        collectionView.center = CGPoint(x: bounds.width / 2, y: gridHeight / 2)
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        if calendarLayout.isRTL != isRTL { updateWeekdays(); needsPagePosition = true }
        calendarLayout.isRTL = isRTL
        if needsPagePosition || needsRepositionForSize {
            let renderedPage = transition?.renderPage ?? page
            if let section = try? engine.sectionIndex(for: renderedPage, scope: renderingMode.scope) {
                collectionView.layoutIfNeeded()
                collectionView.setContentOffset(calendarLayout.offset(for: section), animated: false)
            }
            needsPagePosition = false
        }
    }
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            cancelTransition(); refreshAppearance()
        } else if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            reload(dates: Set(collectionView.visibleCells.compactMap { ($0 as? FSCalendarCell)?.dayState?.occurrence.day }))
        }
    }
    var effectiveRowHeight: CGFloat {
        max(UIFontMetrics(forTextStyle: .body).scaledValue(for: max(24, resolvedAppearance.rowHeight), compatibleWith: traitCollection), resolvedAppearance.titleFont.lineHeight + resolvedAppearance.subtitleFont.lineHeight + 12)
    }
    var effectiveHeaderHeight: CGFloat { max(resolvedAppearance.headerHeight, resolvedAppearance.headerFont.lineHeight + 12) }
    var effectiveWeekdayHeight: CGFloat { max(resolvedAppearance.weekdayHeight, resolvedAppearance.weekdayFont.lineHeight + 4) }
    func rowCount(for day: CivilDay, scope: CalendarScope) -> Int {
        guard scope == .month else { return 1 }
        if configuration.placeholders == .sixRows { return 6 }
        let month = day.startOfMonth
        let leading = (month.weekday - configuration.firstWeekday + 7) % 7
        return (leading + month.daysInMonth + 6) / 7
    }
    func height(for mode: CalendarDisplayMode, page: CivilDay) -> CGFloat {
        effectiveHeaderHeight + effectiveWeekdayHeight + CGFloat(rowCount(for: page, scope: mode.scope)) * effectiveRowHeight
    }
    func clamped(_ day: CivilDay) -> CivilDay { min(configuration.maximumDate, max(configuration.minimumDate, day)) }
    func refreshAppearance() {
        resolvedAppearance = appearance.resolved(for: traitCollection)
        backgroundColor = appearance.backgroundColor
        monthFormatter.calendar = Calendar(identifier: .gregorian)
        monthFormatter.locale = configuration.locale; monthFormatter.timeZone = configuration.timeZone
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        accessibilityFormatter.calendar = monthFormatter.calendar
        accessibilityFormatter.locale = configuration.locale; accessibilityFormatter.timeZone = configuration.timeZone
        accessibilityFormatter.dateStyle = .full; accessibilityFormatter.timeStyle = .none
        titleLabel.font = resolvedAppearance.headerFont; titleLabel.textColor = appearance.headerColor
        updateWeekdays()
        rebuild(mode: mode); updateHeader(); notifyHeight(animated: false)
    }
    func updateWeekdays() {
        let symbols = monthFormatter.veryShortStandaloneWeekdaySymbols ?? []
        for (index, view) in weekdayStack.arrangedSubviews.enumerated() {
            guard let label = view as? UILabel, symbols.count == 7 else { continue }
            let column = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 6 - index : index
            let weekday = (configuration.firstWeekday - 1 + column) % 7
            label.text = symbols[weekday]; label.font = resolvedAppearance.weekdayFont; label.textColor = .secondaryLabel
            label.accessibilityLabel = monthFormatter.standaloneWeekdaySymbols?[weekday]
        }
    }
    func rebuild(mode: CalendarDisplayMode) {
        renderingMode = mode
        calendarLayout.mode = mode
        calendarLayout.rowHeight = effectiveRowHeight; calendarLayout.headerHeight = effectiveHeaderHeight
        calendarLayout.rows = (0..<engine.pageCount(scope: mode.scope)).map { index in
            guard let id = try? engine.page(at: index, scope: mode.scope) else { return 0 }
            return rowCount(for: id.anchor, scope: mode.scope)
        }
        collectionView.isPagingEnabled = !mode.isContinuous
        updateGestureAvailability(); reloadData()
    }
    func updateHeader() {
        if let date = try? page.date(in: configuration.timeZone) { titleLabel.text = monthFormatter.string(from: date) }
    }
    func notifyHeight(animated: Bool) {
        invalidateIntrinsicContentSize()
        guard let delegate else { return }
        let height = preferredHeight
        guard lastDeliveredHeight != height else { return }
        lastDeliveredHeight = height
        delegate.calendar(self, preferredHeightDidChange: height, animated: animated)
    }
    @objc private func clockDidChange() { today = try? CivilDay(date: Date(), timeZone: configuration.timeZone) }
    func grid(in section: Int) -> CalendarGrid? {
        guard let id = try? engine.page(at: section, scope: renderingMode.scope) else { return nil }
        if let cached = gridCache[id] {
            cacheOrder.removeAll { $0 == id }; cacheOrder.append(id)
            return cached
        }
        guard let grid = try? engine.grid(containing: id.anchor, scope: id.scope) else { return nil }
        gridCache[id] = grid; cacheOrder.append(id)
        while cacheOrder.count > 9 { gridCache.removeValue(forKey: cacheOrder.removeFirst()) }
        return grid
    }
    func configure(_ cell: FSCalendarCell, occurrence: DayOccurrence) {
        let content = dataSource?.calendar(self, contentFor: occurrence.day) ?? DayContent()
        let style = dataSource?.calendar(self, appearanceFor: occurrence.day) ?? DayAppearance()
        cell.apply(content: content, state: DayState(occurrence: occurrence, isSelected: selection.contains(occurrence.day), isToday: today == occurrence.day),
                   appearance: resolvedAppearance, style: style)
        cell.accessibilityLabel = content.accessibilityLabel ?? (try? occurrence.day.date(in: configuration.timeZone)).map(accessibilityFormatter.string(from:)) ?? occurrence.day.description
        if configuration.selectionMode == .disabled { cell.accessibilityTraits.insert(.notEnabled) }
    }
    public func numberOfSections(in collectionView: UICollectionView) -> Int { calendarLayout.rows.count }
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { calendarLayout.rows[section] * 7 }
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let grid = grid(in: indexPath.section), grid.occurrences.indices.contains(indexPath.item) else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: "default", for: indexPath)
        }
        let occurrence = grid.occurrences[indexPath.item]
        let requested = dataSource?.calendar(self, reuseIdentifierFor: occurrence.day) ?? "default"
        let identifier = registeredIdentifiers.contains(requested) ? requested : "default"
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath) as! FSCalendarCell
        configure(cell, occurrence: occurrence)
        return cell
    }
    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "month", for: indexPath) as! CalendarMonthHeader
        if let day = try? engine.page(at: indexPath.section, scope: .month).anchor,
           let date = try? day.date(in: configuration.timeZone) { header.label.text = monthFormatter.string(from: date) }
        header.label.font = resolvedAppearance.headerFont; header.label.textColor = appearance.headerColor
        header.backgroundColor = appearance.backgroundColor
        return header
    }
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        transition == nil && configuration.selectionMode != .disabled && (grid(in: indexPath.section)?.occurrences[indexPath.item].isSelectable ?? false)
    }
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? FSCalendarCell, let occurrence = cell.dayState?.occurrence {
            // A prefetched cell may have been configured before the latest selection or content update.
            configure(cell, occurrence: occurrence)
            synchronizeSelection(at: indexPath, day: occurrence.day)
            applyTransitionOpacity(to: cell, at: indexPath)
        }
    }
    func synchronizeSelection(at index: IndexPath, day: CivilDay) {
        if selection.contains(day) { collectionView.selectItem(at: index, animated: false, scrollPosition: []) }
        else { collectionView.deselectItem(at: index, animated: false) }
    }
    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        transition == nil && configuration.selectionMode == .multiple
    }
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let day = grid(in: indexPath.section)?.occurrences[indexPath.item].day else { return }
        try? transact(selectedDays.filter { $0 != day }, origin: .user)
        reload(dates: [day])
    }
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let occurrence = grid(in: indexPath.section)?.occurrences[indexPath.item] else { return }
        let day = occurrence.day
        let next = configuration.selectionMode == .multiple ? (selection.contains(day) ? selectedDays.filter { $0 != day } : selectedDays + [day]) : [day]
        try? transact(next, origin: .user)
        reload(dates: [day]) // Also restore visual state if the delegate vetoed the change.
    }
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if renderingMode.isContinuous { updatePageFromScroll() }
    }
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { updatePageFromScroll() }
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { updatePageFromScroll() }
    func updatePageFromScroll() {
        guard !isLayingOut, !needsPagePosition, transition == nil, collectionView.bounds.width > 0 else { return }
        let section = calendarLayout.section(at: collectionView.contentOffset)
        guard let next = try? engine.page(at: section, scope: mode.scope).anchor, next != page else { return }
        let previousHeight = preferredHeight
        page = next; updateHeader(); updatePageHeight(from: previousHeight, animated: true)
        delegate?.calendarCurrentPageDidChange(self)
    }
    func updateGestureAvailability() {
        scopeGesture.isEnabled = scopeGestureEnabled && renderingMode != .month(.vertical) && !renderingMode.isContinuous
    }
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x) && (mode == .week ? velocity.y > 0 : velocity.y < 0)
    }
    @objc private func scopePan(_ gesture: UIPanGestureRecognizer) { handleScopeGesture(gesture) }
    @objc private func selectionPan(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { swipeVisited.removeAll(); return }
        guard let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
              let occurrence = grid(in: path.section)?.occurrences[path.item], occurrence.isSelectable else { return }
        let day = occurrence.day
        if gesture.state == .began { swipeVisited.removeAll(); swipeRemoves = selection.contains(day) }
        guard swipeVisited.insert(day).inserted else { return }
        let next = swipeRemoves ? selectedDays.filter { $0 != day }
            : (configuration.selectionMode == .multiple ? selectedDays + [day] : [day])
        try? transact(next, origin: .user)
    }
}
#endif
