import UIKit
@preconcurrency import FSCalendarLegacy

@MainActor
final class LegacyCalendarDriver: NSObject, CalendarDemoDriver, @preconcurrency FSCalendarDataSource, @preconcurrency FSCalendarDelegate, @preconcurrency FSCalendarDelegateAppearance {
    let calendar = FSCalendarLegacy.FSCalendar(frame: CGRect(x: 0, y: 0, width: 350, height: 320))
    let scenario: DemoScenario
    var onChange: (() -> Void)?
    var onHeightChange: ((CGFloat, Bool) -> Void)?
    private(set) var events: [String] = []
    var view: UIView { calendar }
    var state: DemoState {
        DemoState(page: calendar.currentPage, scope: calendar.scope == .month ? "month" : "week",
                  selection: calendar.selectedDates, events: events)
    }

    init(scenario: DemoScenario) {
        self.scenario = scenario
        super.init()
        calendar.dataSource = self
        calendar.delegate = self
        calendar.timeZone = DemoFixtures.calendar.timeZone
        calendar.locale = DemoFixtures.calendar.locale!
        calendar.firstWeekday = scenario == .bounds ? 2 : 1
        calendar.accessibilityIdentifier = "calendar"
        calendar.register(FSCalendarCell.self, forCellReuseIdentifier: "default")
        calendar.backgroundColor = .secondarySystemGroupedBackground
        calendar.appearance.titleDefaultColor = .label
        calendar.appearance.titlePlaceholderColor = .tertiaryLabel
        calendar.appearance.headerTitleColor = .label
        calendar.appearance.weekdayTextColor = .secondaryLabel
        calendar.appearance.selectionColor = .systemIndigo
        calendar.appearance.todayColor = .systemOrange
        calendar.appearance.headerDateFormat = "MMMM yyyy"
        calendar.appearance.titleFont = .preferredFont(forTextStyle: .body)
        calendar.appearance.headerTitleFont = .preferredFont(forTextStyle: .headline)
        calendar.appearance.subtitleFont = .preferredFont(forTextStyle: .caption2)
        calendar.appearance.weekdayFont = .preferredFont(forTextStyle: .caption1)
        calendar.allowsMultipleSelection = [.multiple, .swipe, .range].contains(scenario)
        calendar.swipeToChooseGesture.isEnabled = [.swipe, .range].contains(scenario)
        calendar.placeholderType = scenario == .hidden ? .none : ([.variable, .dynamicHeight].contains(scenario) ? .fillHeadTail : .fillSixRows)
        calendar.adjustsBoundingRectWhenChangingMonths = [.variable, .dynamicHeight].contains(scenario)
        if scenario == .vertical { calendar.scrollDirection = .vertical }
        if scenario == .continuous { calendar.pagingEnabled = false; calendar.rowHeight = 52 }
        if scenario == .week { calendar.scope = .week }
        if scenario == .rtl { calendar.semanticContentAttribute = .forceRightToLeft }
        if scenario == .largeText {
            calendar.appearance.titleFont = .systemFont(ofSize: 26)
            calendar.appearance.headerTitleFont = .systemFont(ofSize: 25, weight: .semibold)
        }
        if [.custom, .range].contains(scenario) { calendar.register(DemoLegacyCell.self, forCellReuseIdentifier: "custom") }
        reset()
    }

    func reset() {
        for date in calendar.selectedDates { calendar.deselect(date) }
        calendar.setScope(scenario == .week ? .week : .month, animated: false)
        calendar.setCurrentPage(DemoFixtures.initialDate, animated: false)
        calendar.today = nil
        events.removeAll()
        calendar.reloadData()
        onChange?()
    }
    func navigate(_ offset: Int) {
        let unit: Calendar.Component = calendar.scope == .month ? .month : .weekOfYear
        let next = DemoFixtures.calendar.date(byAdding: unit, value: offset, to: calendar.currentPage)!
        calendar.setCurrentPage(next, animated: true)
    }
    func select(_ date: Date) { calendar.select(date, scrollToDate: false); onChange?() }
    func deselect(_ date: Date) { calendar.deselect(date); onChange?() }
    func toggleScope() {
        guard scenario != .continuous else { return }
        calendar.setScope(calendar.scope == .month ? .week : .month, animated: true)
        onChange?()
    }
    func handleScopeGesture(_ gesture: UIPanGestureRecognizer) { calendar.handleScopeGesture(gesture); onChange?() }
    func reloadContent() { calendar.reloadData(); onChange?() }
    func minimumDate(for calendar: FSCalendarLegacy.FSCalendar) -> Date {
        scenario == .bounds ? DemoFixtures.date("2024-02-10") : DemoFixtures.minimumDate
    }
    func maximumDate(for calendar: FSCalendarLegacy.FSCalendar) -> Date {
        scenario == .bounds ? DemoFixtures.date("2024-03-20") : DemoFixtures.maximumDate
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, subtitleFor date: Date) -> String? {
        scenario == .content ? DemoFixtures.lunarSubtitle(date) : nil
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, titleFor date: Date) -> String? {
        scenario == .content && DemoFixtures.calendar.component(.day, from: date) == 1 ? "1st" : nil
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, appearance: FSCalendarAppearance, titleDefaultColorFor date: Date) -> UIColor? {
        scenario == .content && DemoFixtures.calendar.component(.day, from: date) == 14 ? .systemPink : nil
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, appearance: FSCalendarAppearance, borderDefaultColorFor date: Date) -> UIColor? {
        scenario == .content && DemoFixtures.calendar.component(.day, from: date) == 14 ? .systemPink : nil
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, numberOfEventsFor date: Date) -> Int {
        [.content, .custom].contains(scenario) ? DemoFixtures.calendar.component(.day, from: date) % 4 : 0
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, imageFor date: Date) -> UIImage? {
        scenario == .content && DemoFixtures.calendar.component(.day, from: date) == 14 ? UIImage(systemName: "heart.fill") : nil
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, cellFor date: Date, at position: FSCalendarMonthPosition) -> FSCalendarCell {
        calendar.dequeueReusableCell(withIdentifier: [.custom, .range].contains(scenario) ? "custom" : "default", for: date, at: position)
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, willDisplay cell: FSCalendarCell, for date: Date, at position: FSCalendarMonthPosition) {
        // Identify the date grid rather than the separate collection view used by the month header.
        var ancestor = cell.superview
        while let view = ancestor {
            if let collectionView = view as? UICollectionView {
                collectionView.accessibilityIdentifier = "calendar-grid"
                break
            }
            ancestor = view.superview
        }
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = DemoFixtures.text(date)
        let offset = position == .previous ? 1 : (position == .next ? -1 : 0)
        let owningMonth = DemoFixtures.calendar.date(byAdding: .month, value: offset, to: DemoFixtures.calendar.dateInterval(of: .month, for: date)!.start)!
        cell.accessibilityIdentifier = "day.\(DemoFixtures.text(date)).\(position.rawValue).\(DemoFixtures.text(owningMonth))"
        cell.accessibilityTraits = cell.isSelected ? [.button, .selected] : [.button]
        cell.dateIsToday = DemoFixtures.calendar.isDate(date, inSameDayAs: DemoFixtures.initialDate)
        cell.configureAppearance()
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, didSelect date: Date, at position: FSCalendarMonthPosition) {
        if scenario == .range, calendar.selectedDates.count == 2 {
            let sorted = calendar.selectedDates.sorted()
            var date = sorted[0]
            while date <= sorted[1] {
                calendar.select(date, scrollToDate: false)
                date = DemoFixtures.calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
        append("selected \(DemoFixtures.text(date))")
    }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, didDeselect date: Date, at position: FSCalendarMonthPosition) {
        append("deselected \(DemoFixtures.text(date))")
    }
    func calendarCurrentPageDidChange(_ calendar: FSCalendarLegacy.FSCalendar) { append("page \(DemoFixtures.text(calendar.currentPage))") }
    func calendar(_ calendar: FSCalendarLegacy.FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        onHeightChange?(bounds.height, animated)
        onChange?()
    }
    private func append(_ event: String) {
        events.append(event)
        if events.count > 40 { events.removeFirst(events.count - 40) }
        onChange?()
    }
}

@MainActor
final class DemoLegacyCell: FSCalendarCell {
    override func configureAppearance() {
        super.configureAppearance()
        shapeLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerRadius: 8).cgPath
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    }
}
