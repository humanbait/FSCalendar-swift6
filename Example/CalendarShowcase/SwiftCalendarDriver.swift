import CalendarDemoSupport
import UIKit
import FSCalendar
import FSCalendarCore

@MainActor final class SwiftCalendarDriver: UIKitCalendarDemoDriver, FSCalendarDataSource, FSCalendarDelegate {
    let calendar = FSCalendar(frame: CGRect(x: 0, y: 0, width: 350, height: 340))
    let scenario: DemoScenario
    var onChange: (() -> Void)?
    var onHeightChange: ((CGFloat, Bool) -> Void)?
    private var requestedMode: CalendarDisplayMode?
    private var deliveredHeight: CGFloat?
    private(set) var events: [String] = []
    var view: UIView { calendar }
    var initialHeight: CGFloat { [.continuous, .connectedRange].contains(scenario) ? 400 : calendar.preferredHeight }
    var state: DemoState {
        DemoState(page: (try? calendar.currentPage.date(in: DemoFixtures.calendar.timeZone)) ?? DemoFixtures.initialDate,
                  scope: calendar.displayMode.scope.rawValue, selection: calendar.selectedDates, events: events)
    }
    private var initialMode: CalendarDisplayMode {
        switch scenario {
        case .continuous, .connectedRange: .continuousMonths
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
            selectionMode: [.multiple, .swipe, .range, .connectedRange].contains(scenario) ? .multiple : .single)
        try! calendar.apply(configuration: configuration)
        calendar.delegate = self; calendar.dataSource = self
        calendar.accessibilityIdentifier = "calendar"
        // Interactive scope forwards a container pan; connected range switches only through its button.
        calendar.scopeGestureEnabled = ![.scope, .connectedRange].contains(scenario)
        calendar.swipeSelectionEnabled = [.swipe, .range].contains(scenario)
        if [.custom, .range].contains(scenario) { try! calendar.register(DemoSwiftCell.self, forCellReuseIdentifier: "custom") }
        if scenario == .connectedRange {
            try! calendar.register(ConnectedRangeSwiftCell.self, forCellReuseIdentifier: "connected")
            var appearance = calendar.appearance
            appearance.backgroundColor = .clear
            appearance.alternatingMonthBackgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.06)
                    : UIColor.black.withAlphaComponent(0.04)
            }
            appearance.monthSeparatorCornerRadius = 8
            calendar.appearance = appearance
        }
        if scenario == .rtl { calendar.semanticContentAttribute = .forceRightToLeft }
        reset()
    }
    func reset() {
        requestedMode = nil
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
        let monthMode: CalendarDisplayMode = scenario == .connectedRange ? .continuousMonths : .month(.horizontal)
        let current = calendar.transitionState == .idle ? calendar.displayMode : (requestedMode ?? calendar.displayMode)
        let target: CalendarDisplayMode = current == .week ? monthMode : .week
        requestedMode = target
        perform { try calendar.setDisplayMode(target) }
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
                          numberOfEvents: scenario == .connectedRange ? DemoFixtures.connectedRangeEventCount(dayOfMonth: day.day) :
                            ([.content, .custom].contains(scenario) ? day.day % 4 : 0))
    }
    func calendar(_ calendar: FSCalendar, appearanceFor day: CivilDay) -> DayAppearance {
        if scenario == .range { return DayAppearance(cornerRadius: 8) }
        if scenario == .content && day.day == 14 { return DayAppearance(titleColor: .systemPink, borderColor: .systemPink) }
        return DayAppearance()
    }
    func calendar(_ calendar: FSCalendar, reuseIdentifierFor day: CivilDay) -> String? {
        if scenario == .connectedRange {
            return "connected"
        }
        return [.custom, .range].contains(scenario) ? "custom" : nil
    }
    func calendar(_ calendar: FSCalendar, shouldApply change: SelectionChange) -> Bool {
        scenario != .connectedRange || change.origin != .user || change.removed.isEmpty
    }
    func calendar(_ calendar: FSCalendar, didChangeSelection change: SelectionChange) {
        append("selection +\(change.added.map(\.description).joined(separator: ",")) -\(change.removed.map(\.description).joined(separator: ",")) [\(change.origin.rawValue)]")
        if scenario == .connectedRange {
            Task { @MainActor [weak self] in
                guard let self, self.calendar.selectedDays == change.selection else { return }
                if change.origin == .user, change.selection.count > 1,
                   let first = change.selection.min(), let last = change.selection.max() {
                    var days: [CivilDay] = [], cursor = first
                    while cursor <= last {
                        days.append(cursor)
                        guard let next = try? cursor.addingDays(1) else { break }
                        cursor = next
                    }
                    self.perform { try self.calendar.setSelection(days) }
                }
                self.calendar.reload(dates: Set(self.calendar.selectedDays))
            }
        }
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
    func calendar(_ calendar: FSCalendar, didChangeDisplayMode mode: CalendarDisplayMode) {
        if scenario == .connectedRange {
            deliverHeight(mode.isContinuous ? 400 : calendar.preferredHeight, animated: false)
        }
        append("mode \(mode.scope.rawValue)")
    }
    func calendar(_ calendar: FSCalendar, preferredHeightDidChange height: CGFloat, animated: Bool) {
        if scenario != .continuous {
            let fixedViewport = scenario == .connectedRange && calendar.displayMode.isContinuous && calendar.transitionState == .idle
            deliverHeight(fixedViewport ? 400 : height, animated: animated)
        }
        onChange?()
    }
    private func deliverHeight(_ height: CGFloat, animated: Bool) {
        guard height != deliveredHeight else { return }
        deliveredHeight = height
        onHeightChange?(height, animated)
    }
    private func append(_ event: String) {
        events.append(event)
        if events.count > 40 { events.removeFirst(events.count - 40) }
        onChange?()
    }
}

@MainActor class ConnectedRangeSwiftCell: FSCalendarCell {
    private var normalEventColor: UIColor = .clear
    private var selectedEventColor: UIColor = .clear
    // A layer supplies decoration without adding an input or accessibility target.
    private let eventIndicator: CALayer = {
        let layer = CALayer()
        layer.name = "connectedRange.event"; layer.cornerRadius = 2; layer.isHidden = true
        layer.zPosition = 1 // Stay above the selection background when native subviews reorder their layers.
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull(), "hidden": NSNull()]
        return layer
    }()

    override func apply(content: DayContent, state: DayState, appearance: FSCalendarAppearance, style: DayAppearance) {
        var baseContent = content
        baseContent.numberOfEvents = 0 // This example owns its single event indicator.
        super.apply(content: baseContent, state: state, appearance: appearance, style: style)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        if eventIndicator.superlayer == nil { contentView.layer.addSublayer(eventIndicator) }
        eventIndicator.isHidden = content.numberOfEvents == 0
        normalEventColor = style.eventColor ?? appearance.eventColor
        selectedEventColor = appearance.selectedTitleColor
        eventIndicator.backgroundColor = (state.isSelected ? appearance.selectedTitleColor :
            (style.eventColor ?? appearance.eventColor)).resolvedColor(with: traitCollection).cgColor
        if content.numberOfEvents > 0 {
            let value = [accessibilityValue, "Has events"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            accessibilityValue = value
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let subtitleHeight = subtitleLabel.frame.height * subtitleLabel.alpha
        titleLabel.frame.origin = CGPoint(x: bounds.midX - titleLabel.frame.width / 2,
                                          y: bounds.midY - (titleLabel.frame.height + subtitleHeight) / 2)
        subtitleLabel.frame.origin.y = titleLabel.frame.maxY
        selectionBackground.frame.origin.y = bounds.midY - selectionBackground.frame.height / 2
        eventIndicator.frame = CGRect(x: bounds.midX - 2,
                                      y: min(bounds.maxY - 4, titleLabel.frame.maxY + subtitleHeight + 3), width: 4, height: 4)
        let outsideSelection = subtitleHeight > 0 && eventIndicator.frame.maxY > selectionBackground.frame.maxY
        eventIndicator.backgroundColor = (isSelected && !outsideSelection ? selectedEventColor : normalEventColor)
            .resolvedColor(with: traitCollection).cgColor
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner,
                                        .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        guard let day = dayState?.occurrence.day, dayState?.isSelected == true else {
            selectionBackground.layer.maskedCorners = allCorners
            return
        }
        var ancestor = superview
        while ancestor != nil && !(ancestor is FSCalendar) { ancestor = ancestor?.superview }
        let calendar = ancestor as? FSCalendar
        let selected = Set(calendar?.selectedDays ?? [])
        let previous = (try? day.addingDays(-1)).map(selected.contains) ?? false
        let next = (try? day.addingDays(1)).map(selected.contains) ?? false
        let role = ConnectedRangeBand.role(previousSelected: previous, nextSelected: next,
                                           weekday: day.weekday, firstWeekday: calendar?.configuration.firstWeekday ?? 1)
        // Fractional column widths can leave a hairline between separately rendered cells.
        let overlap = 1 / max(1, traitCollection.displayScale)
        // Keep the connected band as tall as the inherited today circle.
        var frame = CGRect(x: bounds.minX, y: selectionBackground.frame.minY,
                           width: bounds.width, height: selectionBackground.frame.height)
        if role == .middle || role == .trailing { frame.origin.x -= overlap; frame.size.width += overlap }
        if role == .middle || role == .leading { frame.size.width += overlap }
        selectionBackground.frame = frame
        selectionBackground.layer.borderWidth = 0
        selectionBackground.layer.cornerRadius = selectionBackground.bounds.height / 2
        selectionBackground.layer.maskedCorners = switch role {
        case .single: allCorners
        case .leading: [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        case .middle: []
        case .trailing: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        eventIndicator.isHidden = true; eventIndicator.backgroundColor = nil
        selectionBackground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner,
                                                    .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
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
