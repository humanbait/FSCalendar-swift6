import AppKit
import CalendarDemoSupportMac
import FSCalendarAppKit

@MainActor final class ShowcaseController: NSViewController {
    let scenarios = NSPopUpButton(frame: .zero, pullsDown: false)
    let calendar = FSCalendarView(frame: .zero)
    let readout = NSTextField(wrappingLabelWithString: "Mac harness ready — renderer milestone follows.")
    override func loadView() {
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
    @objc private func control(_ sender: NSButton) { readout.stringValue = "\(sender.title) — harness action" }
}
