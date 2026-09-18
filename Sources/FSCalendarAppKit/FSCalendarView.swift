#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

/// A native calendar. Its view, provider, delegate, and mutation APIs are main-actor isolated.
@MainActor public final class FSCalendarView: NSView {
    public weak var delegate: (any FSCalendarDelegate)?
    public weak var dataSource: (any FSCalendarDataSource)? { didSet { reloadData() } }
    public var calendarAppearance = FSCalendarAppearance() { didSet { rebuild() } }
    public var today: CivilDay? { didSet { reload(dates: Set([oldValue, today].compactMap { $0 })) } }
    public var configuration: CalendarConfiguration { engine.configuration }
    public var selectedDays: [CivilDay] { selection.days }
    public var selectedDate: Date? { selection.latest.flatMap { try? $0.date(in: configuration.timeZone) } }
    public var selectedDates: [Date] { selectedDays.compactMap { try? $0.date(in: configuration.timeZone) } }
    public private(set) var focusedDay: CivilDay?
    public var swipeSelectionEnabled = false
    public var currentPage: CivilDay { page }
    public var displayMode: CalendarDisplayMode { mode }
    public var preferredHeight: CGFloat { height(for: page) }
    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: mode.isContinuous ? NSView.noIntrinsicMetric : preferredHeight) }
    public override var fittingSize: NSSize { NSSize(width: bounds.width, height: preferredHeight) }
    var selection = SelectionState()
    var isMutating = false
    let input = CalendarInputController()
    var engine = try! CalendarEngine(configuration: CalendarConfiguration())
    var page = try! CivilDay(year: 1970, month: 1, day: 1)
    var mode: CalendarDisplayMode = .month(.horizontal)
    let calendarLayout = CalendarCollectionLayout()
    let collectionView = CalendarCollectionView()
    let scrollView = CalendarScrollView()
    let titleLabel = NSTextField(labelWithString: "")
    let weekdayLabels = (0..<7).map { _ in NSTextField(labelWithString: "") }
    let controller = CalendarCollectionController()
    var needsPagePosition = true
    var lastSize = NSSize.zero
    var isLayingOut = false
    var cachedPageCount: Int { controller.cache.count }
    var metrics: FSCalendarAppearance { calendarAppearance.resolved() }
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect); setUp() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setUp() }
    private func setUp() {
        wantsLayer = true
        today = try? CivilDay(date: Date(), timeZone: configuration.timeZone)
        page = engine.pageID(containing: clamped(today ?? configuration.minimumDate), scope: .month).anchor
        controller.owner = self; input.owner = self; scrollView.owner = self
        collectionView.autoresizingMask = []
        collectionView.collectionViewLayout = calendarLayout; collectionView.dataSource = controller; collectionView.delegate = controller
        collectionView.isSelectable = true; collectionView.allowsMultipleSelection = true; collectionView.backgroundColors = [.clear]
        collectionView.register(FSCalendarItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("default"))
        collectionView.register(CalendarMonthHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("month"))
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        collectionView.setAccessibilityIdentifier("calendar-grid")
        scrollView.hasHorizontalScroller = true; scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true; scrollView.scrollerStyle = .overlay
        scrollView.setAccessibilityIdentifier("calendar.scroll")
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        addSubview(scrollView); addSubview(titleLabel)
        titleLabel.alignment = .center; titleLabel.setAccessibilityIdentifier("calendar.heading")
        for label in weekdayLabels { label.alignment = .center; addSubview(label) }
        setAccessibilityIdentifier("calendar"); rebuild()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    public func apply(configuration: CalendarConfiguration) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        let replacement = try CalendarEngine(configuration: configuration)
        isMutating = true; defer { isMutating = false }
        let change = selection.pruningChange(for: replacement)
        engine = replacement
        if let change { selection.commit(change) }
        let oldPage = page
        page = engine.pageID(containing: clamped(page), scope: mode.scope).anchor
        reconcileFocus(); rebuild()
        if let change { delegate?.calendar(self, didChangeSelection: change) }
        if oldPage != page { delegate?.calendarCurrentPageDidChange(self) }
    }

    public func setCurrentPage(_ day: CivilDay, animated: Bool = false) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        let index = try engine.sectionIndex(for: day, scope: mode.scope)
        let next = try engine.page(at: index, scope: mode.scope).anchor
        let changed = next != page
        page = next; reconcileFocus(); needsPagePosition = true
        updateHeader(); notifyHeight(animated: animated)
        needsLayout = true; layoutSubtreeIfNeeded()
        if changed { delegate?.calendarCurrentPageDidChange(self) }
    }
    public func setCurrentPage(_ date: Date, animated: Bool = false) throws {
        try setCurrentPage(CivilDay(date: date, timeZone: configuration.timeZone), animated: animated)
    }
    public func navigate(_ offset: Int, animated: Bool = true) throws {
        let index = try engine.sectionIndex(for: page, scope: mode.scope)
        let (next, overflow) = index.addingReportingOverflow(offset)
        guard !overflow else { throw CalendarError.invalidPageIndex(offset) }
        try setCurrentPage(engine.page(at: next, scope: mode.scope).anchor, animated: animated)
    }
    public func setDisplayMode(_ target: CalendarDisplayMode, animated: Bool = true) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        guard target != mode else { return }
        let plan = transitionPlan(to: target), previous = page
        mode = target; page = plan.destinationPage; reconcileFocus(); rebuild()
        needsLayout = true; layoutSubtreeIfNeeded()
        delegate?.calendar(self, didChangeDisplayMode: mode)
        if page != previous { delegate?.calendarCurrentPageDidChange(self) }
    }
    func transitionPlan(to target: CalendarDisplayMode) -> CalendarTransitionPlan {
        let visible = collectionView.visibleItems().compactMap { item -> CivilDay? in
            guard item.view.frame.intersects(collectionView.visibleRect), let state = (item as? FSCalendarItem)?.dayState,
                  !state.occurrence.isHidden else { return nil }
            return state.occurrence.day
        }
        return CalendarTransitionPlan(engine: engine, currentPage: page, visibleDays: visible,
            selectedDays: selectedDays, today: today, targetMode: target)
    }
    public func select(_ day: CivilDay) throws {
        try setSelection(configuration.selectionMode == .multiple ? selectedDays + [day] : [day])
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
        selection.commit(change); reload(dates: Set(change.added + change.removed))
        delegate?.calendar(self, didChangeSelection: change)
    }
    public func focus(_ day: CivilDay) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        guard day >= configuration.minimumDate, day <= configuration.maximumDate else { throw CalendarError.outOfBounds(day) }
        _ = try day.date(in: configuration.timeZone)
        if engine.pageID(containing: day, scope: mode.scope).anchor != page { try setCurrentPage(day) }
        let old = focusedDay; focusedDay = day
        reload(dates: Set([old, day].compactMap { $0 }))
        NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
    }
    func firstEligibleDay() -> CivilDay {
        (try? engine.grid(containing: page, scope: mode.scope))?.occurrences.first { $0.isSelectable && $0.position == .current }?.day ?? clamped(page)
    }
    func reconcileFocus() {
        guard let focusedDay else { return }
        if !engine.isSelectable(focusedDay) || engine.pageID(containing: focusedDay, scope: mode.scope).anchor != page {
            self.focusedDay = firstEligibleDay()
        }
    }
    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool {
        if focusedDay == nil { focusedDay = firstEligibleDay() }
        reload(dates: Set([focusedDay].compactMap { $0 })); return true
    }
    public override func resignFirstResponder() -> Bool { reload(dates: Set([focusedDay].compactMap { $0 })); return true }
    public override func keyDown(with event: NSEvent) {
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        switch event.keyCode {
        case 123: input.moveFocus(rtl ? 1 : -1)
        case 124: input.moveFocus(rtl ? -1 : 1)
        case 125: input.moveFocus(7)
        case 126: input.moveFocus(-7)
        case 49: input.activate(focusedDay ?? firstEligibleDay())
        case 116: try? navigate(-1)
        case 121: try? navigate(1)
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default: super.keyDown(with: event)
        }
    }
    public func register(_ itemClass: FSCalendarItem.Type, forItemReuseIdentifier identifier: String) throws {
        guard !identifier.isEmpty else { throw CalendarError.invalidConfiguration("Item reuse identifier must not be empty") }
        controller.registered.insert(identifier)
        collectionView.register(itemClass, forItemWithIdentifier: NSUserInterfaceItemIdentifier(identifier))
    }
    public func reloadData() { controller.cache.removeAll(); controller.recency.removeAll(); collectionView.reloadData(); needsLayout = true }
    public func reload(dates: Set<CivilDay>) {
        for case let item as FSCalendarItem in collectionView.visibleItems() {
            if let occurrence = item.dayState?.occurrence, dates.contains(occurrence.day) { configure(item, occurrence: occurrence) }
        }
    }
    func configure(_ item: FSCalendarItem, occurrence: DayOccurrence) {
        var content = dataSource?.calendar(self, contentFor: occurrence.day) ?? DayContent()
        if content.accessibilityLabel == nil {
            content.accessibilityLabel = (try? occurrence.day.date(in: configuration.timeZone)).map { formatter("EEEE, MMMM d, yyyy").string(from: $0) }
        }
        item.view.effectiveAppearance.performAsCurrentDrawingAppearance {
        item.apply(content: content, state: DayState(occurrence: occurrence, isSelected: selection.contains(occurrence.day), isToday: occurrence.day == today),
            appearance: metrics, style: dataSource?.calendar(self, appearanceFor: occurrence.day) ?? DayAppearance())
        }
        (item.view as? CalendarDayView)?.owner = self
        item.view.layer?.borderWidth = focusedDay == occurrence.day && window?.firstResponder === self ? 2 : 0
        item.view.layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
        item.view.layer?.cornerRadius = 4

    }
    func clamped(_ day: CivilDay) -> CivilDay { min(configuration.maximumDate, max(configuration.minimumDate, day)) }
    func rowCount(_ day: CivilDay) -> Int {
        if mode == .week { return 1 }
        if configuration.placeholders == .sixRows { return 6 }
        return ((day.startOfMonth.weekday - configuration.firstWeekday + 7) % 7 + day.daysInMonth + 6) / 7
    }
    func height(for day: CivilDay) -> CGFloat { metrics.headerHeight + metrics.weekdayHeight + CGFloat(rowCount(day)) * metrics.rowHeight }
    func rebuild() {
        input.cancelScroll()
        calendarLayout.mode = mode; calendarLayout.rowHeight = metrics.rowHeight; calendarLayout.headerHeight = metrics.headerHeight
        calendarLayout.rows = (0..<engine.pageCount(scope: mode.scope)).compactMap { try? engine.page(at: $0, scope: mode.scope) }.map { rowCount($0.anchor) }
        calendarLayout.invalidateLayout(); reloadData(); updateHeader(); notifyHeight(animated: false)
        needsPagePosition = true; needsLayout = true
    }
    func notifyHeight(animated: Bool) {
        invalidateIntrinsicContentSize(); delegate?.calendar(self, preferredHeightDidChange: preferredHeight, animated: animated)
    }
    func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian)
        value.locale = configuration.locale; value.timeZone = configuration.timeZone; value.dateFormat = format; return value
    }
    func updateHeader() {
        let appearance = metrics
        titleLabel.stringValue = (try? page.date(in: configuration.timeZone)).map { formatter("LLLL yyyy").string(from: $0) } ?? page.description
        titleLabel.font = appearance.headerFont; titleLabel.textColor = appearance.headerColor
        let symbols = formatter("EEE").shortWeekdaySymbols!, full = formatter("EEEE").weekdaySymbols!
        for (column, label) in weekdayLabels.enumerated() {
            let weekday = (configuration.firstWeekday - 1 + (userInterfaceLayoutDirection == .rightToLeft ? 6 - column : column)) % 7
            label.stringValue = symbols[weekday]; label.setAccessibilityLabel(full[weekday]); label.font = appearance.weekdayFont
        }
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = appearance.backgroundColor.cgColor }
    }
    @objc private func scrolled() {
        guard mode.isContinuous, !isLayingOut, !needsPagePosition else { return }
        let section = calendarLayout.section(at: scrollView.contentView.bounds.origin)
        guard let next = try? engine.page(at: section, scope: .month).anchor, next != page else { return }
        page = next; reconcileFocus(); updateHeader(); delegate?.calendarCurrentPageDidChange(self)
    }
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); calendarLayout.rowHeight = metrics.rowHeight; needsPagePosition = true; needsLayout = true
    }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateHeader(); reload(dates: Set(collectionView.visibleItems().compactMap { ($0 as? FSCalendarItem)?.dayState?.occurrence.day }))
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); needsPagePosition = true; needsLayout = true
    }
    public override func layout() {
        super.layout()
        guard !isLayingOut else { return }; isLayingOut = true; defer { isLayingOut = false }
        let appearance = metrics
        let headerHeight: CGFloat = mode.isContinuous ? 0 : appearance.headerHeight
        titleLabel.isHidden = mode.isContinuous
        titleLabel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        for (index, label) in weekdayLabels.enumerated() {
            label.frame = NSRect(x: CGFloat(index) * bounds.width / 7, y: headerHeight, width: bounds.width / 7, height: appearance.weekdayHeight)
        }
        let top = headerHeight + appearance.weekdayHeight
        scrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(1, bounds.height - top))
        if calendarLayout.viewport != scrollView.contentSize || calendarLayout.isRTL != (userInterfaceLayoutDirection == .rightToLeft) {
            calendarLayout.viewport = scrollView.contentSize
            calendarLayout.isRTL = userInterfaceLayoutDirection == .rightToLeft
            calendarLayout.invalidateLayout(); needsPagePosition = true; updateHeader()
        }
        if collectionView.frame.size != calendarLayout.collectionViewContentSize { collectionView.frame.size = calendarLayout.collectionViewContentSize }
        scrollView.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
        if needsPagePosition || lastSize != bounds.size {
            if let section = try? engine.sectionIndex(for: page, scope: mode.scope) {
                scrollView.contentView.scroll(to: calendarLayout.offset(for: section)); scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            needsPagePosition = false
        }
        if lastSize != bounds.size { updateHeader() }
        lastSize = bounds.size
    }
}
#endif
