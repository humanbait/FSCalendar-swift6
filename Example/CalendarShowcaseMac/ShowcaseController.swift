import AppKit
import CalendarDemoSupportMac
import FSCalendarAppKit

@MainActor final class DemoCanvas: NSView { override var isFlipped: Bool { true } }

@MainActor final class ShowcaseController: NSViewController {
    let scenarios = NSPopUpButton(frame: .zero, pullsDown: false)
    let sidebar = NSScrollView()
    let sidebarContent = DemoCanvas()
    let contentScroll = NSScrollView()
    let content = DemoCanvas()
    let readout = NSTextField()
    let eventReadout = NSTextView()
    let eventsScroll = NSScrollView()
    let scopeHandle = NSButton(title: "Drag to change month / week", target: nil, action: nil)
    let agenda = NSScrollView()
    let agendaText = NSTextView()
    var driver: AppKitCalendarDriver!
    var scenario: DemoScenario = .month
    var controls: [NSButton] = []
    var sidebarButtons: [NSButton] = []
    var sidebarHeadings: [NSTextField] = []
    override func loadView() {
        view = DemoCanvas(frame: NSRect(x: 0, y: 0, width: 1080, height: 820))
        scenarios.menu = NSMenu()
        for (index, group) in DemoScenario.groups.enumerated() {
            if index > 0 { scenarios.menu?.addItem(.separator()) }
            let heading = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            scenarios.menu?.addItem(heading)
            for scenario in group.scenarios {
                scenarios.addItem(withTitle: scenario == .swipe ? "Mouse-drag selection" : scenario.title)
                scenarios.lastItem?.representedObject = scenario.rawValue
            }
        }
        scenarios.target = self; scenarios.action = #selector(chooseScenario(_:))
        scenarios.setAccessibilityIdentifier("scenario.selector")
        view.addSubview(scenarios)
        for title in ["Previous", "Next", "Reset", "Month / Week", "Reload"] {
            let button = NSButton(title: title, target: self, action: #selector(control(_:)))
            button.setAccessibilityIdentifier(title == "Month / Week" ? "scope.toggle" : title.lowercased())
            controls.append(button); view.addSubview(button)
        }
        sidebar.documentView = sidebarContent; sidebar.hasVerticalScroller = true; sidebar.autohidesScrollers = true
        sidebar.drawsBackground = false; view.addSubview(sidebar)
        for group in DemoScenario.groups {
            let heading = NSTextField(labelWithString: group.title)
            heading.font = .boldSystemFont(ofSize: 12)
            heading.textColor = .secondaryLabelColor
            sidebarHeadings.append(heading); sidebarContent.addSubview(heading)
            for scenario in group.scenarios {
                let button = NSButton(title: scenario == .swipe ? "Mouse-drag selection" : scenario.title, target: self, action: #selector(sidebarChoice(_:)))
                button.tag = DemoScenario.allCases.firstIndex(of: scenario)!
                button.bezelStyle = .recessed; button.alignment = .left
                button.setAccessibilityIdentifier("scenario.\(scenario.rawValue)")
                sidebarButtons.append(button); sidebarContent.addSubview(button)
            }
        }
        contentScroll.documentView = content; contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true; contentScroll.drawsBackground = false
        view.addSubview(contentScroll)
        readout.isEditable = false; readout.isSelectable = true; readout.isBordered = false; readout.drawsBackground = false
        readout.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        readout.setAccessibilityRole(.textField); readout.setAccessibilityIdentifier("state.readout")
        content.addSubview(readout)
        eventReadout.isEditable = false; eventReadout.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        eventReadout.setAccessibilityIdentifier("state.events"); eventsScroll.documentView = eventReadout
        eventsScroll.hasVerticalScroller = true; eventsScroll.borderType = .lineBorder
        content.addSubview(eventsScroll)
        scopeHandle.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(scopePan(_:))))
        scopeHandle.target = self; scopeHandle.action = #selector(toggleScopeFromHandle)
        scopeHandle.setAccessibilityIdentifier("scope.handle"); content.addSubview(scopeHandle)
        agendaText.isEditable = false; agendaText.font = .systemFont(ofSize: 15)
        agendaText.string = (1...40).map { "Agenda item \($0) — scrolling this list keeps the calendar mode unchanged." }.joined(separator: "\n\n")
        agenda.documentView = agendaText; agenda.hasVerticalScroller = true
        agenda.setAccessibilityIdentifier("agenda"); content.addSubview(agenda)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--scenario"), arguments.indices.contains(index + 1), let requested = DemoScenario(rawValue: arguments[index + 1]) { scenario = requested }
        show(scenario)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.appearance = view.appearance
    }
    func show(_ scenario: DemoScenario) {
        driver?.view.removeFromSuperview()
        self.scenario = scenario; driver = AppKitCalendarDriver(scenario: scenario)
        content.addSubview(driver.view)
        driver.onChange = { [weak self] in self?.updateReadout() }
        driver.onHeightChange = { [weak self] _, _ in self?.view.needsLayout = true }
        if let index = scenarios.itemArray.firstIndex(where: { $0.representedObject as? String == scenario.rawValue }) {
            scenarios.selectItem(at: index)
        }
        for button in sidebarButtons { button.state = DemoScenario.allCases[button.tag] == scenario ? .on : .off }
        view.appearance = scenario == .dark ? NSAppearance(named: .darkAqua) : nil
        view.window?.appearance = view.appearance
        scopeHandle.isHidden = scenario != .scope; agenda.isHidden = scenario != .scope
        updateReadout(); view.needsLayout = true
        contentScroll.contentView.scroll(to: .zero)
    }
    @objc private func scopePan(_ gesture: NSPanGestureRecognizer) { driver.handleScopeGesture(gesture) }
    @objc private func toggleScopeFromHandle() { driver.toggleScope() }
    @objc private func chooseScenario(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let scenario = DemoScenario(rawValue: rawValue) else { return }
        show(scenario)
    }
    @objc private func sidebarChoice(_ sender: NSButton) { show(DemoScenario.allCases[sender.tag]) }
    @objc private func control(_ sender: NSButton) {
        switch sender.title {
        case "Previous": driver.navigate(-1)
        case "Next": driver.navigate(1)
        case "Reset": driver.reset()
        case "Reload": driver.reloadContent()
        default: driver.toggleScope()
        }
        updateReadout(); view.needsLayout = true
    }
    private func updateReadout() {
        guard let driver else { return }
        readout.stringValue = "Page: \(DemoFixtures.text(driver.state.page)) • \(driver.state.scope) • selected: \(driver.state.selection.map(DemoFixtures.text).joined(separator: ","))"
        eventReadout.string = driver.state.events.suffix(8).joined(separator: "\n")
        driver.calendar.setAccessibilityValue("\(driver.calendar.displayMode.scope.rawValue) \(driver.calendar.currentPage)")
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let driver else { return }
        let width = view.bounds.width, height = view.bounds.height
        scenarios.frame = NSRect(x: 20, y: 18, width: 200, height: 28)
        var x: CGFloat = 244
        for button in controls { let w: CGFloat = button.title == "Month / Week" ? 125 : 85; button.frame = NSRect(x: x, y: 18, width: w, height: 28); x += w + 8 }
        sidebar.frame = NSRect(x: 16, y: 60, width: 212, height: max(200, height - 80))
        var sidebarY: CGFloat = 0
        var buttonIndex = 0
        for (index, group) in DemoScenario.groups.enumerated() {
            sidebarHeadings[index].frame = NSRect(x: 8, y: sidebarY, width: 194, height: 24)
            sidebarY += 26
            for _ in group.scenarios {
                sidebarButtons[buttonIndex].frame = NSRect(x: 0, y: sidebarY, width: 202, height: 30)
                sidebarY += 34; buttonIndex += 1
            }
            sidebarY += 8
        }
        sidebarContent.frame = NSRect(x: 0, y: 0, width: 204, height: sidebarY)
        contentScroll.frame = NSRect(x: 244, y: 60, width: max(350, width - 264), height: max(250, height - 80))
        let contentWidth = contentScroll.contentSize.width
        let continuousViewport = scenario == .continuous || (scenario == .connectedRange && driver.calendar.displayMode.isContinuous)
        let calendarHeight = continuousViewport ? CGFloat(420) : driver.calendar.preferredHeight
        let total = calendarHeight + (scenario == .scope ? 350 : 160)
        content.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(contentScroll.contentSize.height, total))
        driver.view.frame = NSRect(x: 0, y: 0, width: contentWidth, height: calendarHeight)
        readout.frame = NSRect(x: 0, y: calendarHeight + 12, width: contentWidth, height: 24)
        eventsScroll.frame = NSRect(x: 0, y: calendarHeight + 44, width: contentWidth, height: 90)
        eventReadout.frame.size = NSSize(width: contentWidth, height: 150)
        scopeHandle.frame = NSRect(x: 0, y: calendarHeight + 146, width: contentWidth, height: 28)
        agenda.frame = NSRect(x: 0, y: calendarHeight + 184, width: contentWidth, height: 150)
        agendaText.frame.size = NSSize(width: contentWidth, height: 2000)
    }
}
