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
    public var currentPage: CivilDay { page }
    public var displayMode: CalendarDisplayMode { mode }
    public var preferredHeight: CGFloat { height(for: page) }
    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: preferredHeight) }
    public override var fittingSize: NSSize { NSSize(width: bounds.width, height: preferredHeight) }
    var engine = try! CalendarEngine(configuration: CalendarConfiguration())
    var page = try! CivilDay(year: 1970, month: 1, day: 1)
    var mode: CalendarDisplayMode = .month(.horizontal)
    let calendarLayout = CalendarCollectionLayout()
    let collectionView = NSCollectionView()
    let scrollView = NSScrollView()
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
        controller.owner = self
        collectionView.collectionViewLayout = calendarLayout; collectionView.dataSource = controller; collectionView.delegate = controller
        collectionView.isSelectable = false; collectionView.backgroundColors = [.clear]
        collectionView.register(FSCalendarItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("default"))
        collectionView.setAccessibilityIdentifier("calendar-grid")
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        addSubview(scrollView); addSubview(titleLabel)
        titleLabel.alignment = .center; titleLabel.setAccessibilityIdentifier("calendar.heading")
        for label in weekdayLabels { label.alignment = .center; addSubview(label) }
        setAccessibilityIdentifier("calendar"); rebuild()
    }
    public func apply(configuration: CalendarConfiguration) throws {
        engine = try CalendarEngine(configuration: configuration)
        let oldPage = page
        page = engine.pageID(containing: clamped(page), scope: mode.scope).anchor
        rebuild()
        if oldPage != page { delegate?.calendarCurrentPageDidChange(self) }
    }
    public func setCurrentPage(_ day: CivilDay, animated: Bool = false) throws {
        let index = try engine.sectionIndex(for: day, scope: mode.scope)
        let next = try engine.page(at: index, scope: mode.scope).anchor
        let changed = next != page
        page = next; needsPagePosition = true
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
        item.apply(content: content, state: DayState(occurrence: occurrence, isSelected: false, isToday: occurrence.day == today),
            appearance: metrics, style: dataSource?.calendar(self, appearanceFor: occurrence.day) ?? DayAppearance())
    }
    func clamped(_ day: CivilDay) -> CivilDay { min(configuration.maximumDate, max(configuration.minimumDate, day)) }
    func rowCount(_ day: CivilDay) -> Int {
        if mode == .week { return 1 }
        if configuration.placeholders == .sixRows { return 6 }
        return ((day.startOfMonth.weekday - configuration.firstWeekday + 7) % 7 + day.daysInMonth + 6) / 7
    }
    func height(for day: CivilDay) -> CGFloat { metrics.headerHeight + metrics.weekdayHeight + CGFloat(rowCount(day)) * metrics.rowHeight }
    func rebuild() {
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
        layer?.backgroundColor = appearance.backgroundColor.cgColor
    }
    public override func layout() {
        super.layout()
        guard !isLayingOut else { return }; isLayingOut = true; defer { isLayingOut = false }
        let appearance = metrics
        titleLabel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: appearance.headerHeight)
        for (index, label) in weekdayLabels.enumerated() {
            label.frame = NSRect(x: CGFloat(index) * bounds.width / 7, y: appearance.headerHeight, width: bounds.width / 7, height: appearance.weekdayHeight)
        }
        let top = appearance.headerHeight + appearance.weekdayHeight
        scrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(1, bounds.height - top))
        calendarLayout.viewport = scrollView.contentSize
        calendarLayout.isRTL = userInterfaceLayoutDirection == .rightToLeft
        calendarLayout.invalidateLayout()
        collectionView.frame.size = calendarLayout.collectionViewContentSize
        if needsPagePosition || lastSize != bounds.size {
            if let section = try? engine.sectionIndex(for: page, scope: mode.scope) {
                scrollView.contentView.scroll(to: calendarLayout.offset(for: section)); scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            needsPagePosition = false
        }
        lastSize = bounds.size
    }
}
#endif
