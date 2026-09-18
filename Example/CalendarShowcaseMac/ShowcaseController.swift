import AppKit
import CalendarDemoSupportMac
import FSCalendarAppKit
import FSCalendarCore

@MainActor final class ShowcaseController: NSViewController, FSCalendarDelegate {
    let scenarios = NSPopUpButton(frame: .zero, pullsDown: false)
    let calendar = FSCalendarView(frame: .zero)
    let readout = NSTextField()
    override func loadView() {
        try! calendar.apply(configuration: CalendarConfiguration(timeZone: DemoFixtures.calendar.timeZone, locale: DemoFixtures.calendar.locale!, selectionMode: .multiple))
        try! calendar.setCurrentPage(DemoFixtures.initialDate)
        calendar.today = try! CivilDay(date: DemoFixtures.initialDate, timeZone: DemoFixtures.calendar.timeZone)
        calendar.delegate = self
        calendar.swipeSelectionEnabled = true
        readout.isEditable = false; readout.isSelectable = true; readout.isBordered = false; readout.drawsBackground = false
        readout.setAccessibilityRole(.textField)
        readout.setAccessibilityIdentifier("state.readout")
        updateReadout()
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 750))
        scenarios.addItems(withTitles: DemoScenario.allCases.map(\.title))
        scenarios.setAccessibilityIdentifier("scenario.selector")
        let controls = NSStackView(views: [scenarios] + ["Previous", "Next", "Reset"].map {
            let button = NSButton(title: $0, target: self, action: #selector(control(_:)))
            button.setAccessibilityIdentifier($0.lowercased()); return button
        })
        controls.orientation = .horizontal
        let stack = NSStackView(views: [controls, calendar, readout]); stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            calendar.widthAnchor.constraint(equalTo: stack.widthAnchor), calendar.heightAnchor.constraint(equalToConstant: 340)])
    }
    @objc private func control(_ sender: NSButton) {
        do {
            switch sender.title {
            case "Previous": try calendar.navigate(-1)
            case "Next": try calendar.navigate(1)
            default: try calendar.setCurrentPage(DemoFixtures.initialDate)
            }
            readout.stringValue = "Page: \(calendar.currentPage)"
        } catch { readout.stringValue = "Rejected: \(error)" }
    }
    func calendarCurrentPageDidChange(_ calendar: FSCalendarView) { updateReadout() }
    func calendar(_ calendar: FSCalendarView, didChangeSelection change: SelectionChange) { updateReadout() }
    private func updateReadout() { readout.stringValue = "Page: \(calendar.currentPage) selected: \(calendar.selectedDays.map(\.description).joined(separator: ","))" }
}
