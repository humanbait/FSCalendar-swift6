import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit
import CalendarDemoSupportMac
@testable import CalendarShowcaseMac

final class AppKitScenarioTests: XCTestCase {
    @MainActor func testConnectedScopeContainerFramesAndNativeCaptures() async throws {
        let controller = ShowcaseController(); _ = controller.view; controller.show(.connectedRange)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1080, height: 820),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = controller
        window.center(); window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let calendar = controller.driver.calendar
        let boundary = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
        try calendar.setSelection(boundary)
        try calendar.setCurrentPage(boundary[0]); calendar.layoutSubtreeIfNeeded()
        let pixel = 1 / window.backingScaleFactor
        var trace: [[String: Any]] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for target: CalendarDisplayMode in [.week, .continuousMonths] {
                calendar.prepareTransition(to: target)
                let context = try XCTUnwrap(calendar.transition)
                XCTAssertEqual(context.targetHeight, target.isContinuous ? 420 : calendar.height(for: boundary[1], mode: .week))
                for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                    calendar.updateInteractiveTransition(progress: progress)
                    XCTAssertEqual(calendar.frame.height, calendar.preferredHeight, accuracy: pixel)
                    XCTAssertEqual(controller.readout.frame.minY, calendar.frame.maxY + 12, accuracy: pixel)
                    XCTAssertEqual(controller.eventsScroll.frame.minY, calendar.frame.maxY + 44, accuracy: pixel)
                    XCTAssertEqual(controller.agenda.frame.minY, calendar.frame.maxY + 184, accuracy: pixel)
                    XCTAssertEqual(calendar.titleLabel.frame.maxY, calendar.weekdayLabels[0].frame.minY, accuracy: pixel)
                    let cells = calendar.collectionView.visibleItems().compactMap { $0 as? ConnectedRangeAppKitItem }
                    for day in boundary {
                        let cell = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == day })
                        XCTAssertEqual(cell.view.alphaValue, 1)
                        XCTAssertTrue(cell.dayState?.isSelected == true)
                        XCTAssertFalse(try XCTUnwrap(cell.view.layer?.sublayers?.first { $0.name == "connectedRange.event" }).isHidden)
                        XCTAssertTrue(((cell.view.accessibilityValue() as? String) ?? "").contains("Has events"))
                        XCTAssertEqual(cell.view.layer?.borderWidth, 0)
                    }
                    window.displayIfNeeded(); CATransaction.flush()
                    trace.append(["appearance": name, "target": target.isContinuous ? "continuous" : "week",
                                  "progress": Double(progress), "height": Double(calendar.frame.height),
                                  "headerHeight": Double(calendar.titleLabel.frame.height),
                                  "scrollOffset": Double(calendar.scrollView.contentView.bounds.minY)])
                    // Capture the WindowServer composite: cacheDisplay omits selective band corner masks.
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
                    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
                    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                        do { try process.run() } catch { continuation.resume(throwing: error) }
                    }
                    let attachment: XCTAttachment
                    if status == 0, let image = NSImage(contentsOf: url) { attachment = XCTAttachment(image: image) }
                    else { attachment = XCTAttachment(string: "Native window capture unavailable (status \(status)); check Screen Recording permission.") }
                    attachment.name = "appkit-scope-\(name)-\(target.isContinuous ? "expand" : "collapse")-\(Int(progress * 100))"
                    attachment.lifetime = .keepAlways; add(attachment)
                    try? FileManager.default.removeItem(at: url)
                }
                let height = calendar.frame.height
                calendar.finishInteractiveTransition(commit: true, animated: false)
                XCTAssertEqual(calendar.frame.height, height, accuracy: pixel)
                XCTAssertEqual(controller.readout.frame.minY, height + 12, accuracy: pixel)
                XCTAssertNil(calendar.transition)
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "appkit-scope-frame-trace"; attachment.lifetime = .keepAlways; add(attachment)
        calendar.reduceMotionOverride = false
        controller.driver.toggleScope()
        let context = try XCTUnwrap(calendar.transition)
        controller.driver.toggleScope()
        XCTAssertTrue(calendar.transition === context); XCTAssertFalse(context.settlingCommit)
        let returned = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated { calendar.transitionState == .idle } }, evaluatedWith: nil)
        await fulfillment(of: [returned], timeout: 3)
        XCTAssertEqual(calendar.displayMode, .continuousMonths); XCTAssertEqual(calendar.frame.height, 420)
    }

    @MainActor func testAllNineteenScenariosRenderNavigateSelectAndReset() throws {
        XCTAssertEqual(DemoScenario.allCases.count, 19)
        for scenario in DemoScenario.allCases {
            let driver = AppKitCalendarDriver(scenario: scenario)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = driver.view; window.orderFront(nil)
            driver.view.layoutSubtreeIfNeeded()
            driver.select(DemoFixtures.initialDate)
            XCTAssertEqual(driver.state.selection, [DemoFixtures.initialDate], scenario.rawValue)
            let original = driver.state.page
            driver.navigate(1); driver.navigate(-1)
            XCTAssertEqual(driver.state.page, original, scenario.rawValue)
            driver.reloadContent()
            XCTAssertEqual(driver.state.selection, [DemoFixtures.initialDate], scenario.rawValue)
            driver.reset()
            XCTAssertTrue(driver.state.selection.isEmpty, scenario.rawValue)
            XCTAssertTrue(driver.state.events.isEmpty, scenario.rawValue)
            window.close()
        }
    }
    @MainActor func testContentCustomItemsLargeFontsAndDarkAppearance() throws {
        for scenario: DemoScenario in [.content, .custom, .range, .largeText, .dark] {
            let driver = AppKitCalendarDriver(scenario: scenario)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: driver.calendar.preferredHeight), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = driver.view; window.orderFront(nil)
            driver.view.layoutSubtreeIfNeeded()
            let collection = try XCTUnwrap(driver.view.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSCollectionView)
            let item = try XCTUnwrap(collection.visibleItems().compactMap { $0 as? FSCalendarItem }.first { $0.dayState?.occurrence.day.day == 14 })
            if scenario == .content {
                XCTAssertEqual(item.subtitleLabel.stringValue, DemoFixtures.lunarSubtitle(DemoFixtures.initialDate))
                XCTAssertNotNil(item.dayImageView.image)
            }
            if [.custom, .range].contains(scenario) { XCTAssertTrue(item is DemoAppKitItem) }
            if scenario == .largeText { XCTAssertEqual(item.titleLabel.font?.pointSize, 28) }
            if scenario == .dark { XCTAssertEqual(driver.calendar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua) }
            window.close()
        }
    }
    @MainActor func testConnectedRangeCenteredTitlesAndEventReuse() throws {
        let driver = AppKitCalendarDriver(scenario: .connectedRange)
        for number in 1...31 {
            let day = try CivilDay(year: 2024, month: 3, day: number)
            let content = driver.calendar(driver.calendar, contentFor: day)
            XCTAssertEqual(content.numberOfEvents, [1, 5, 9, 14, 18, 22, 29].contains(number) ? 1 : 0)
        }
        let cell = ConnectedRangeAppKitItem()
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        let occurrence = try XCTUnwrap(CalendarEngine(configuration: CalendarConfiguration())
            .continuousMonthGrid(containing: day).occurrences.first { $0.day == day })
        var appearance = FSCalendarAppearance()
        appearance.eventColor = .red; appearance.selectedTitleColor = .white
        for size in [CGSize(width: 56, height: 44), CGSize(width: 70.3, height: 59.5), CGSize(width: 117, height: 44)] {
            let reference = FSCalendarItem()
            reference.view.frame = CGRect(origin: .zero, size: size)
            reference.apply(content: DayContent(),
                state: DayState(occurrence: occurrence, isSelected: false, isToday: true),
                appearance: appearance, style: DayAppearance())
            reference.viewDidLayout()
            let todayDiameter = reference.selectionBackground.frame.height
            for rtl in [false, true] {
                cell.view.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                for selected in [false, true] {
                    for count in [0, 1, 5] {
                        for title in ["14", "Mar"] {
                            cell.view.frame = CGRect(origin: .zero, size: size)
                            cell.apply(content: DayContent(title: title, numberOfEvents: count),
                                state: DayState(occurrence: occurrence, isSelected: selected, isToday: true),
                                appearance: appearance, style: DayAppearance())
                            cell.viewDidLayout()
                            let layers = (cell.view.layer?.sublayers ?? []).filter { $0.name == "connectedRange.event" }
                            XCTAssertEqual(layers.count, 1)
                            let dot = try XCTUnwrap(layers.first)
                            XCTAssertEqual(cell.titleLabel.frame.midX, size.width / 2, accuracy: 0.001)
                            XCTAssertEqual(cell.titleLabel.frame.midY, size.height / 2, accuracy: 0.001)
                            XCTAssertEqual(cell.selectionBackground.frame.midY, size.height / 2, accuracy: 0.001)
                            XCTAssertEqual(cell.selectionBackground.frame.height, todayDiameter, accuracy: 0.001)
                            XCTAssertEqual(dot.frame.midX, size.width / 2, accuracy: 0.001)
                            XCTAssertEqual(dot.frame.minY - cell.titleLabel.frame.maxY, 3, accuracy: 0.001)
                            XCTAssertEqual(dot.frame.size, CGSize(width: 4, height: 4))
                            XCTAssertGreaterThan(dot.zPosition, cell.selectionBackground.layer?.zPosition ?? 0)
                            XCTAssertLessThanOrEqual(dot.frame.maxY, size.height - 3)
                            XCTAssertEqual(dot.isHidden, count == 0)
                            XCTAssertEqual(dot.backgroundColor, (selected ? appearance.selectedTitleColor : appearance.eventColor).cgColor)
                            let value = (cell.view.accessibilityValue() as? String) ?? ""
                            XCTAssertEqual(value.components(separatedBy: "Has events").count - 1, count > 0 ? 1 : 0)
                            XCTAssertTrue(value.lowercased().contains("today"))
                            XCTAssertEqual(value.contains("selected"), selected)
                            let baseDots = cell.view.subviews.filter { $0 !== cell.selectionBackground && !($0 is NSTextField) && !($0 is NSImageView) }
                            XCTAssertTrue(baseDots.allSatisfy(\.isHidden))
                        }
                    }
                }
            }
        }
        cell.apply(content: DayContent(numberOfEvents: 1, accessibilityValue: "Meeting"),
            state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
            appearance: appearance, style: DayAppearance(eventColor: .green))
        let dot = try XCTUnwrap((cell.view.layer?.sublayers ?? []).first { $0.name == "connectedRange.event" })
        XCTAssertEqual(dot.backgroundColor, NSColor.green.cgColor)
        XCTAssertTrue(((cell.view.accessibilityValue() as? String) ?? "").contains("Meeting"))
        appearance.eventColor = .labelColor
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            cell.view.appearance = NSAppearance(named: name)
            cell.view.effectiveAppearance.performAsCurrentDrawingAppearance {
                cell.apply(content: DayContent(numberOfEvents: 1),
                    state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                    appearance: appearance, style: DayAppearance())
                XCTAssertEqual(dot.backgroundColor, NSColor.labelColor.cgColor)
            }
        }
        cell.prepareForReuse()
        XCTAssertTrue(dot.isHidden)
        XCTAssertNil(dot.backgroundColor)
        cell.apply(content: DayContent(), state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                   appearance: appearance, style: DayAppearance())
        XCTAssertTrue(dot.isHidden)
        XCTAssertFalse(((cell.view.accessibilityValue() as? String) ?? "").contains("Has events"))
    }

    @MainActor func testConnectedRangeBandGeometryAndReuse() throws {
        let driver = AppKitCalendarDriver(scenario: .connectedRange)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = driver.view; window.orderFront(nil)
        defer { window.close() }
        let days = try (16...20).map { try CivilDay(date: DemoFixtures.date("2024-02-\($0)"), timeZone: DemoFixtures.calendar.timeZone) }
        try driver.calendar.setSelection(days)
        driver.calendar.reloadData(); driver.view.layoutSubtreeIfNeeded()
        let collection = try XCTUnwrap(driver.view.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSCollectionView)
        func band(_ number: Int) throws -> ConnectedRangeAppKitItem {
            let expectedDay = days[number - 16]
            return try XCTUnwrap(collection.visibleItems().compactMap { $0 as? ConnectedRangeAppKitItem }.first {
                $0.dayState?.occurrence.day == expectedDay && $0.dayState?.occurrence.position == .current
            })
        }
        let friday = try band(16), saturday = try band(17), sunday = try band(18)
        let monday = try band(19), tuesday = try band(20)
        let left: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        let right: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        XCTAssertEqual(friday.selectionBackground.layer?.maskedCorners, left)
        XCTAssertEqual(saturday.selectionBackground.layer?.maskedCorners, right)
        XCTAssertEqual(sunday.selectionBackground.layer?.maskedCorners, left)
        XCTAssertEqual(monday.selectionBackground.layer?.maskedCorners, [])
        XCTAssertEqual(tuesday.selectionBackground.layer?.maskedCorners, right)
        XCTAssertGreaterThan(friday.selectionBackground.frame.width, friday.view.bounds.width)
        XCTAssertEqual(friday.view.frame.maxX, saturday.view.frame.minX, accuracy: 0.5)
        XCTAssertGreaterThan(friday.selectionBackground.frame.maxX, friday.view.bounds.maxX)
        XCTAssertLessThan(saturday.selectionBackground.frame.minX, saturday.view.bounds.minX)

        let boundary = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
        try driver.calendar.setSelection(boundary)
        try driver.calendar.setCurrentPage(boundary[1], animated: false)
        driver.calendar.reloadData(); driver.view.layoutSubtreeIfNeeded()
        let boundaryCells = collection.visibleItems().compactMap { $0 as? ConnectedRangeAppKitItem }
        let february = try XCTUnwrap(boundaryCells.first { $0.dayState?.occurrence.day == boundary[0] })
        let march = try XCTUnwrap(boundaryCells.first { $0.dayState?.occurrence.day == boundary[1] })
        XCTAssertEqual(february.view.frame.minY, march.view.frame.minY, accuracy: 0.5)
        XCTAssertEqual(february.view.frame.maxX, march.view.frame.minX, accuracy: 0.5)
        XCTAssertEqual(february.selectionBackground.layer?.maskedCorners, left)
        XCTAssertEqual(march.selectionBackground.layer?.maskedCorners, right)
        XCTAssertEqual(boundaryCells.filter { $0.dayState?.occurrence.day == boundary[0] }.count, 1)
        XCTAssertEqual(march.titleLabel.stringValue, "Mar")
        for cell in [february, march] {
            let dot = try XCTUnwrap((cell.view.layer?.sublayers ?? []).first { $0.name == "connectedRange.event" })
            XCTAssertFalse(dot.isHidden)
            XCTAssertEqual(cell.titleLabel.frame.midY, cell.view.bounds.midY, accuracy: 0.01)
            XCTAssertEqual(dot.backgroundColor, NSColor.white.cgColor)
            XCTAssertTrue(((cell.view.accessibilityValue() as? String) ?? "").contains("Has events"))
            XCTAssertTrue((cell.view.accessibilityLabel() ?? "").contains("2024"))
        }
        driver.calendar.reload(dates: Set(boundary))
        XCTAssertEqual(((march.view.accessibilityValue() as? String) ?? "").components(separatedBy: "Has events").count, 2)

        for mode: CalendarDisplayMode in [.week, .continuousMonths] {
            try driver.calendar.setDisplayMode(mode, animated: false)
            driver.view.layoutSubtreeIfNeeded()
            let cell = try XCTUnwrap(collection.visibleItems().compactMap { $0 as? FSCalendarItem }.first { $0.dayState?.occurrence.day == boundary[1] })
            XCTAssertEqual(cell.titleLabel.stringValue, mode.isContinuous ? "Mar" : "1")
            XCTAssertEqual(cell.titleLabel.frame.midY, cell.view.bounds.midY, accuracy: 0.01)
            let dot = try XCTUnwrap((cell.view.layer?.sublayers ?? []).first { $0.name == "connectedRange.event" })
            XCTAssertFalse(dot.isHidden)
        }
        try driver.calendar.setCurrentPage(days[0], animated: false)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            driver.view.layoutSubtreeIfNeeded(); driver.view.displayIfNeeded()
            let bitmap = try XCTUnwrap(driver.view.bitmapImageRepForCachingDisplay(in: driver.view.bounds))
            driver.view.cacheDisplay(in: driver.view.bounds, to: bitmap)
            let image = NSImage(size: driver.view.bounds.size); image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
            attachment.name = "appkit-connected-events-\(name)"; attachment.lifetime = .keepAlways
            add(attachment)
        }
        window.appearance = nil

        try driver.calendar.setSelection([days[4]])
        driver.calendar.reloadData(); driver.view.layoutSubtreeIfNeeded()
        let single = try band(20)
        XCTAssertEqual(single.selectionBackground.layer?.maskedCorners,
                       [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner])
        let old = try XCTUnwrap(collection.visibleItems().compactMap { $0 as? FSCalendarItem }.first {
            $0.dayState?.occurrence.day == days[0] && $0.dayState?.occurrence.position == .current
        })
        XCTAssertFalse(old.dayState?.isSelected ?? true)
        XCTAssertLessThan(old.selectionBackground.frame.width, old.view.bounds.width)
    }
    @MainActor func testConnectedRangeCombinedMenuAndContinuousScope() throws {
        XCTAssertEqual(DemoScenario.groups.map(\.title), ["Examples", "Combined usage"])
        XCTAssertEqual(DemoScenario.groups[1].scenarios, [.connectedRange])
        let controller = ShowcaseController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 820),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = controller; window.orderFront(nil)
        defer { window.close() }
        controller.show(.connectedRange); controller.view.layoutSubtreeIfNeeded()
        let driver = try XCTUnwrap(controller.driver)
        XCTAssertEqual(controller.sidebarHeadings.map(\.stringValue), ["Examples", "Combined usage"])
        XCTAssertEqual(controller.scenarios.selectedItem?.representedObject as? String, "connectedRange")
        XCTAssertEqual(driver.calendar.displayMode, .continuousMonths)
        XCTAssertEqual(driver.view.frame.height, 420, accuracy: 0.5)
        let selected = DemoFixtures.date("2024-02-14")
        driver.select(selected)
        func waitForMode(_ mode: CalendarDisplayMode) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { driver.calendar.displayMode == mode }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            controller.view.layoutSubtreeIfNeeded()
        }
        driver.toggleScope(); waitForMode(.week)
        XCTAssertEqual(driver.view.frame.height, driver.calendar.preferredHeight, accuracy: 0.5)
        XCTAssertEqual(driver.state.selection, [selected])
        driver.toggleScope(); waitForMode(.continuousMonths)
        XCTAssertEqual(driver.view.frame.height, 420, accuracy: 0.5)
        XCTAssertEqual(driver.state.selection, [selected])
        driver.reset(); controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(driver.calendar.displayMode, .continuousMonths)
        XCTAssertTrue(driver.state.selection.isEmpty)
        XCTAssertEqual(driver.view.frame.height, 420, accuracy: 0.5)
    }
}
