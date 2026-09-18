import CalendarDemoSupport
import UIKit
import FSCalendar
import FSCalendarCore

@MainActor final class SwiftCalendarDriver: UIKitCalendarDemoDriver, FSCalendarDataSource, FSCalendarDelegate {
    let calendar = FSCalendar(frame: CGRect(x: 0, y: 0, width: 350, height: 340))
    let scenario: DemoScenario
    var onChange: (() -> Void)?
    var onHeightChange: ((CGFloat, Bool) -> Void)?
    private(set) var events: [String] = []
    var view: UIView { calendar }
    var state: DemoState {
        DemoState(page: (try? calendar.currentPage.date(in: DemoFixtures.calendar.timeZone)) ?? DemoFixtures.initialDate,
                  scope: calendar.displayMode.scope.rawValue, selection: calendar.selectedDates, events: events)
    }
    private var initialMode: CalendarDisplayMode {
        switch scenario {
        case .continuous: .continuousMonths
        case .week: .week
        case .vertical: .month(.vertical)
        default: .month(.horizontal)
        }
    }
    init(scenario: DemoScenario) {
        self.scenario = scenario
        let minimum = scenario == .bounds ? DemoFixtures.date("2024-02-10") : DemoFixtures.minimumDate
        let maximum = scenario == .bounds ? DemoFixtures.date("2024-03-20") : DemoFixtures.maximumDate
        let configuration = try! CalendarConfiguration(firstWeekday: scenario == .bounds ? 2 : 1,
            placeholders: scenario == .hidden ? .none : ([.variable, .dynamicHeight].contains(scenario) ? .variable : .sixRows),
            minimumDate: CivilDay(date: minimum, timeZone: DemoFixtures.calendar.timeZone),
            maximumDate: CivilDay(date: maximum, timeZone: DemoFixtures.calendar.timeZone),
            timeZone: DemoFixtures.calendar.timeZone, locale: DemoFixtures.calendar.locale!,
            selectionMode: [.multiple, .swipe, .range].contains(scenario) ? .multiple : .single)
        try! calendar.apply(configuration: configuration)
        calendar.delegate = self; calendar.dataSource = self
        calendar.accessibilityIdentifier = "calendar"
        calendar.scopeGestureEnabled = scenario != .scope // The scope screen forwards its external container pan.
        calendar.swipeSelectionEnabled = [.swipe, .range].contains(scenario)
        if [.custom, .range].contains(scenario) { try! calendar.register(DemoSwiftCell.self, forCellReuseIdentifier: "custom") }
        if scenario == .rtl { calendar.semanticContentAttribute = .forceRightToLeft }
        reset()
    }
    func reset() {
        perform { try calendar.clearSelection(); try calendar.setDisplayMode(initialMode, animated: false)
            try calendar.setCurrentPage(DemoFixtures.initialDate, animated: false) }
        calendar.today = try? CivilDay(date: DemoFixtures.initialDate, timeZone: DemoFixtures.calendar.timeZone)
        events.removeAll(); calendar.reloadData(); onChange?()
    }
    func navigate(_ offset: Int) { perform { try calendar.navigate(offset) } }
    func select(_ date: Date) { perform { try calendar.select(date) } }
    func deselect(_ date: Date) { perform { try calendar.deselect(CivilDay(date: date, timeZone: DemoFixtures.calendar.timeZone)) } }
    func toggleScope() {
        guard scenario != .continuous else { return }
        perform { try calendar.setDisplayMode(calendar.displayMode == .week ? .month(.horizontal) : .week) }
    }
    func handleScopeGesture(_ gesture: UIPanGestureRecognizer) { calendar.handleScopeGesture(gesture) }
    func reloadContent() { calendar.reloadData(); onChange?() }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { append("rejected: \(error)") }
        onChange?()
    }
    func calendar(_ calendar: FSCalendar, contentFor day: CivilDay) -> DayContent {
        let date = try? day.date(in: DemoFixtures.calendar.timeZone)
        return DayContent(title: scenario == .content && day.day == 1 ? "1st" : nil,
                          subtitle: scenario == .content ? date.map(DemoFixtures.lunarSubtitle) : nil,
                          image: scenario == .content && day.day == 14 ? UIImage(systemName: "heart.fill") : nil,
                          numberOfEvents: [.content, .custom].contains(scenario) ? day.day % 4 : 0)
    }
    func calendar(_ calendar: FSCalendar, appearanceFor day: CivilDay) -> DayAppearance {
        if scenario == .range { return DayAppearance(cornerRadius: 8) }
        if scenario == .content && day.day == 14 { return DayAppearance(titleColor: .systemPink, borderColor: .systemPink) }
        return DayAppearance()
    }
    func calendar(_ calendar: FSCalendar, reuseIdentifierFor day: CivilDay) -> String? {
        [.custom, .range].contains(scenario) ? "custom" : nil
    }
    func calendar(_ calendar: FSCalendar, didChangeSelection change: SelectionChange) {
        append("selection +\(change.added.map(\.description).joined(separator: ",")) -\(change.removed.map(\.description).joined(separator: ",")) [\(change.origin.rawValue)]")
        if scenario == .range, change.origin == .user, change.selection.count == 2,
           let first = change.selection.min(), let last = change.selection.max() {
            // Delegate callbacks cannot reenter a selection transaction. Apply the sample range on the next actor turn.
            Task { @MainActor [weak self] in
                guard let self, self.calendar.selectedDays == change.selection else { return }
                var days: [CivilDay] = [], cursor = first
                while cursor <= last {
                    days.append(cursor)
                    guard let next = try? cursor.addingDays(1) else { break }
                    cursor = next
                }
                self.perform { try self.calendar.setSelection(days) }
            }
        }
    }
    func calendarCurrentPageDidChange(_ calendar: FSCalendar) { append("page \(calendar.currentPage)") }
    func calendar(_ calendar: FSCalendar, didChangeDisplayMode mode: CalendarDisplayMode) { append("mode \(mode.scope.rawValue)") }
    func calendar(_ calendar: FSCalendar, preferredHeightDidChange height: CGFloat, animated: Bool) {
        if scenario != .continuous { onHeightChange?(height, animated) }
        onChange?()
    }
    private func append(_ event: String) {
        events.append(event)
        if events.count > 40 { events.removeFirst(events.count - 40) }
        onChange?()
    }
}

@MainActor final class DemoSwiftCell: FSCalendarCell {
    override func apply(content: DayContent, state: DayState, appearance: FSCalendarAppearance, style: DayAppearance) {
        var custom = style; custom.cornerRadius = 8
        super.apply(content: content, state: state, appearance: appearance, style: custom)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        selectionBackground.frame = contentView.bounds.insetBy(dx: 2, dy: 3)
    }
}
