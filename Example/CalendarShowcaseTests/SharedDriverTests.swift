import CalendarDemoSupport
import UIKit
import XCTest
import FSCalendarCore
@testable import FSCalendar
@testable import CalendarShowcase

final class SharedDriverTests: XCTestCase {
    @MainActor private func makeWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return window
    }

    @MainActor func testNavigationKeepsInitialCalendarHeight() {
        let window = (UIApplication.shared.delegate as! AppDelegate).showcaseWindow!
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.makeKeyAndVisible()
        }
        for scenario in [DemoScenario.month, .week, .variable, .continuous, .connectedRange] {
            let page = ScenarioController(scenario: scenario)
            let navigation = UINavigationController(rootViewController: page)
            navigation.loadViewIfNeeded()
            navigation.view.frame = window.bounds
            navigation.view.layoutIfNeeded()
            page.view.layoutIfNeeded()
            let initialHeight = page.driver.view.bounds.height
            let calendar = (page.driver as! SwiftCalendarDriver).calendar
            let expectedHeight: CGFloat = [.continuous, .connectedRange].contains(scenario) ? 400 : calendar.preferredHeight
            XCTAssertEqual(initialHeight, expectedHeight, accuracy: 0.5, scenario.rawValue)
            func capture(_ stage: String) {
                let image = UIGraphicsImageRenderer(bounds: navigation.view.bounds).image { context in
                    navigation.view.layer.render(in: context.cgContext)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(scenario.rawValue)-\(stage)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            capture("before-appearance")
            func pageStateLabel(in view: UIView) -> UIView? {
                if view.accessibilityIdentifier == "page-state" { return view }
                return view.subviews.lazy.compactMap { pageStateLabel(in: $0) }.first
            }
            let stateLabel = pageStateLabel(in: page.view)!
            func waitForAppearance() {
                let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    MainActor.assumeIsolated { stateLabel.accessibilityValue == "portrait" }
                }, object: nil)
                wait(for: [appeared], timeout: 3)
            }
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            waitForAppearance()
            navigation.view.layoutIfNeeded()
            capture("after-appearance")
            XCTAssertEqual(page.driver.view.bounds.height, initialHeight, accuracy: 0.5, scenario.rawValue)
            page.driver.select(DemoFixtures.initialDate)
            let selection = page.driver.state.selection
            let cover = AppearanceController()
            let covered = expectation(description: "Cover appeared")
            cover.onAppear = { covered.fulfill() }
            navigation.pushViewController(cover, animated: false)
            wait(for: [covered], timeout: 3)
            stateLabel.accessibilityValue = nil
            navigation.popViewController(animated: false)
            waitForAppearance()
            navigation.view.layoutIfNeeded()
            XCTAssertEqual(page.driver.view.bounds.height, initialHeight, accuracy: 0.5)
            XCTAssertEqual(page.driver.state.selection, selection)
            window.rootViewController = nil
        }
    }

    @MainActor func testSwiftResetsAndFixedRowNavigationDoNotRepeatHeightCallbacks() throws {
        let driver = SwiftCalendarDriver(scenario: .month)
        let window = host(driver)
        defer { window.isHidden = true }
        var heights: [CGFloat] = []
        driver.onHeightChange = { height, _ in heights.append(height) }
        driver.reset(); driver.reset()
        try driver.calendar.setCurrentPage(DemoFixtures.date("2024-03-01"), animated: false)
        driver.reset()
        XCTAssertTrue(heights.isEmpty)
    }

    @MainActor private func host(_ driver: any UIKitCalendarDemoDriver) -> UIWindow {
        let window = makeWindow()
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(driver.view)
        driver.view.frame = CGRect(x: 0, y: 50, width: 390, height: driver.initialHeight)
        window.makeKeyAndVisible(); driver.view.layoutIfNeeded()
        return window
    }
    @MainActor func testEveryScenarioRendersTheFixture() {
        for scenario in DemoScenario.allCases {
            let driver = SwiftCalendarDriver(scenario: scenario)
            let window = host(driver)
            defer { window.isHidden = true }
            XCTAssertEqual(driver.state.scope, scenario == .week ? "week" : "month", "\(scenario)")
            XCTAssertTrue(DemoFixtures.text(driver.state.page).hasPrefix("2024-02"), "\(scenario): \(driver.state.page)")
            XCTAssertTrue(driver.state.selection.isEmpty)
            func containsFixtureDay(_ view: UIView) -> Bool {
                if view.accessibilityIdentifier?.hasPrefix("day.2024-02-14.1.") == true { return true }
                return view.subviews.contains(where: containsFixtureDay)
            }
            XCTAssertTrue(containsFixtureDay(driver.view), "Missing visible fixture day: \(scenario)")
        }
    }
    @MainActor func testSwiftSelectionAndReloadPersistence() {
        let driver = SwiftCalendarDriver(scenario: .multiple)
        let window = host(driver); defer { window.isHidden = true }
        let a = DemoFixtures.date("2024-02-12"), b = DemoFixtures.date("2024-02-14")
        driver.select(a); driver.select(b); driver.reloadContent(); driver.view.layoutIfNeeded()
        XCTAssertEqual(driver.state.selection, [a, b])
        driver.deselect(a)
        XCTAssertEqual(driver.state.selection, [b])
        driver.reset()
        XCTAssertTrue(driver.state.selection.isEmpty)
    }
    @MainActor func testConnectedRangeCenteredTitlesAndEventReuse() throws {
        let driver = SwiftCalendarDriver(scenario: .connectedRange)
        for number in 1...31 {
            let day = try CivilDay(year: 2024, month: 3, day: number)
            let content = driver.calendar(driver.calendar, contentFor: day)
            XCTAssertEqual(content.numberOfEvents, [1, 5, 9, 14, 18, 22, 29].contains(number) ? 1 : 0)
        }
        let cell = ConnectedRangeSwiftCell(frame: .zero)
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        let occurrence = try XCTUnwrap(CalendarEngine(configuration: CalendarConfiguration())
            .continuousMonthGrid(containing: day).occurrences.first { $0.day == day })
        var appearance = FSCalendarAppearance()
        appearance.eventColor = .red; appearance.selectedTitleColor = .white
        for size in [CGSize(width: 56, height: 44), CGSize(width: 70.3, height: 59.5), CGSize(width: 117, height: 44)] {
            let reference = FSCalendarCell(frame: .zero)
            reference.frame = CGRect(origin: .zero, size: size)
            reference.apply(content: DayContent(),
                state: DayState(occurrence: occurrence, isSelected: false, isToday: true),
                appearance: appearance, style: DayAppearance())
            reference.setNeedsLayout(); reference.layoutIfNeeded()
            let todayDiameter = reference.selectionBackground.frame.height
            for rtl in [false, true] {
                cell.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                for selected in [false, true] {
                    for count in [0, 1, 5] {
                        for title in ["14", "Mar"] {
                            cell.frame = CGRect(origin: .zero, size: size)
                            cell.apply(content: DayContent(title: title, numberOfEvents: count),
                                state: DayState(occurrence: occurrence, isSelected: selected, isToday: true),
                                appearance: appearance, style: DayAppearance())
                            cell.setNeedsLayout(); cell.layoutIfNeeded()
                            let layers = (cell.contentView.layer.sublayers ?? []).filter { $0.name == "connectedRange.event" }
                            XCTAssertEqual(layers.count, 1)
                            let dot = try XCTUnwrap(layers.first)
                            XCTAssertEqual(cell.titleLabel.frame.midX, size.width / 2, accuracy: 0.001)
                            XCTAssertEqual(cell.titleLabel.frame.midY, size.height / 2, accuracy: 0.001)
                            XCTAssertEqual(cell.selectionBackground.frame.midY, size.height / 2, accuracy: 0.001)
                            XCTAssertEqual(cell.selectionBackground.frame.height, todayDiameter, accuracy: 0.001)
                            XCTAssertEqual(dot.frame.midX, size.width / 2, accuracy: 0.001)
                            XCTAssertEqual(dot.frame.minY - cell.titleLabel.frame.maxY, 3, accuracy: 0.001)
                            XCTAssertEqual(dot.frame.size, CGSize(width: 4, height: 4))
                            XCTAssertGreaterThan(dot.zPosition, cell.selectionBackground.layer.zPosition)
                            XCTAssertLessThanOrEqual(dot.frame.maxY, size.height - 3)
                            XCTAssertEqual(dot.isHidden, count == 0)
                            XCTAssertEqual(dot.backgroundColor, (selected ? appearance.selectedTitleColor : appearance.eventColor).cgColor)
                            let value = cell.accessibilityValue ?? ""
                            XCTAssertEqual(value.components(separatedBy: "Has events").count - 1, count > 0 ? 1 : 0)
                            XCTAssertTrue(value.lowercased().contains("today"))
                            XCTAssertEqual(cell.accessibilityTraits.contains(.selected), selected)
                            XCTAssertTrue(cell.contentView.subviews.compactMap { $0 as? UIStackView }.allSatisfy(\.isHidden))
                        }
                    }
                }
            }
        }
        cell.apply(content: DayContent(numberOfEvents: 1, accessibilityValue: "Meeting"),
            state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
            appearance: appearance, style: DayAppearance(eventColor: .green))
        let dot = try XCTUnwrap((cell.contentView.layer.sublayers ?? []).first { $0.name == "connectedRange.event" })
        XCTAssertEqual(dot.backgroundColor, UIColor.green.cgColor)
        XCTAssertTrue((cell.accessibilityValue ?? "").contains("Meeting"))
        appearance.eventColor = .label
        for style: UIUserInterfaceStyle in [.light, .dark] {
            cell.overrideUserInterfaceStyle = style
            cell.apply(content: DayContent(numberOfEvents: 1),
                state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                appearance: appearance, style: DayAppearance())
            XCTAssertEqual(dot.backgroundColor, UIColor.label.resolvedColor(with: cell.traitCollection).cgColor)
        }
        cell.prepareForReuse()
        XCTAssertTrue(dot.isHidden)
        XCTAssertNil(dot.backgroundColor)
        cell.apply(content: DayContent(), state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                   appearance: appearance, style: DayAppearance())
        XCTAssertTrue(dot.isHidden)
        XCTAssertFalse((cell.accessibilityValue ?? "").contains("Has events"))
    }

    @MainActor func testConnectedRangeBandGeometryAndReuse() throws {
        let driver = SwiftCalendarDriver(scenario: .connectedRange)
        let window = host(driver); defer { window.isHidden = true }
        let days = try (16...20).map { try CivilDay(date: DemoFixtures.date("2024-02-\($0)"), timeZone: DemoFixtures.calendar.timeZone) }
        try driver.calendar.setSelection(days)
        driver.calendar.reloadData(); driver.view.layoutIfNeeded()
        func cells(in view: UIView) -> [FSCalendarCell] {
            if let collection = view as? UICollectionView {
                return collection.visibleCells.compactMap { $0 as? FSCalendarCell }
            }
            return view.subviews.flatMap(cells)
        }
        func band(_ number: Int) throws -> ConnectedRangeSwiftCell {
            let expectedDay = days[number - 16]
            return try XCTUnwrap(cells(in: driver.view).compactMap { $0 as? ConnectedRangeSwiftCell }.first {
                $0.dayState?.occurrence.day == expectedDay && $0.dayState?.occurrence.position == .current
            })
        }
        let friday = try band(16), saturday = try band(17), sunday = try band(18)
        let monday = try band(19), tuesday = try band(20)
        let left: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        let right: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        XCTAssertEqual(friday.selectionBackground.layer.maskedCorners, left)
        XCTAssertEqual(saturday.selectionBackground.layer.maskedCorners, right)
        XCTAssertEqual(sunday.selectionBackground.layer.maskedCorners, left)
        XCTAssertEqual(monday.selectionBackground.layer.maskedCorners, [])
        XCTAssertEqual(tuesday.selectionBackground.layer.maskedCorners, right)
        XCTAssertGreaterThan(friday.selectionBackground.frame.width, friday.contentView.bounds.width)
        XCTAssertEqual(friday.frame.maxX, saturday.frame.minX, accuracy: 0.5)
        XCTAssertGreaterThan(friday.selectionBackground.frame.maxX, friday.contentView.bounds.maxX)
        XCTAssertLessThan(saturday.selectionBackground.frame.minX, saturday.contentView.bounds.minX)

        let boundary = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
        try driver.calendar.setSelection(boundary)
        try driver.calendar.setCurrentPage(boundary[1], animated: false)
        driver.calendar.reloadData(); driver.view.layoutIfNeeded()
        let boundaryCells = cells(in: driver.view).compactMap { $0 as? ConnectedRangeSwiftCell }
        let february = try XCTUnwrap(boundaryCells.first { $0.dayState?.occurrence.day == boundary[0] })
        let march = try XCTUnwrap(boundaryCells.first { $0.dayState?.occurrence.day == boundary[1] })
        XCTAssertEqual(february.frame.minY, march.frame.minY, accuracy: 0.5)
        XCTAssertEqual(february.frame.maxX, march.frame.minX, accuracy: 0.5)
        XCTAssertEqual(february.selectionBackground.layer.maskedCorners, left)
        XCTAssertEqual(march.selectionBackground.layer.maskedCorners, right)
        XCTAssertEqual(boundaryCells.filter { $0.dayState?.occurrence.day == boundary[0] }.count, 1)
        XCTAssertEqual(march.titleLabel.text, "Mar")
        for cell in [february, march] {
            let dot = try XCTUnwrap((cell.contentView.layer.sublayers ?? []).first { $0.name == "connectedRange.event" })
            XCTAssertFalse(dot.isHidden)
            XCTAssertEqual(cell.titleLabel.frame.midY, cell.contentView.bounds.midY, accuracy: 0.01)
            XCTAssertEqual(dot.backgroundColor, UIColor.white.cgColor)
            XCTAssertTrue((cell.accessibilityValue ?? "").contains("Has events"))
            XCTAssertTrue((cell.accessibilityLabel ?? "").contains("2024"))
        }
        driver.calendar.reload(dates: Set(boundary))
        XCTAssertEqual((march.accessibilityValue ?? "").components(separatedBy: "Has events").count, 2)

        for mode: CalendarDisplayMode in [.week, .continuousMonths] {
            try driver.calendar.setDisplayMode(mode, animated: false)
            let title = mode.isContinuous ? "Mar" : "1"
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    driver.view.layoutIfNeeded()
                    return cells(in: driver.view).first { $0.dayState?.occurrence.day == boundary[1] }?.titleLabel.text == title
                }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
            let cell = try XCTUnwrap(cells(in: driver.view).first { $0.dayState?.occurrence.day == boundary[1] })
            XCTAssertEqual(cell.titleLabel.text, mode.isContinuous ? "Mar" : "1")
            XCTAssertEqual(cell.titleLabel.frame.midY, cell.contentView.bounds.midY, accuracy: 0.01)
            let dot = try XCTUnwrap((cell.contentView.layer.sublayers ?? []).first { $0.name == "connectedRange.event" })
            XCTAssertFalse(dot.isHidden)
        }
        try driver.calendar.setCurrentPage(days[0], animated: false)
        for (name, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            window.overrideUserInterfaceStyle = style
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    driver.view.layoutIfNeeded()
                    return driver.view.traitCollection.userInterfaceStyle == style &&
                        cells(in: driver.view).contains { $0.dayState?.occurrence.day == boundary[1] }
                }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
            let image = UIGraphicsImageRenderer(bounds: driver.view.bounds).image { _ in
                XCTAssertTrue(driver.view.drawHierarchy(in: driver.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "swift-connected-events-\(name)"; attachment.lifetime = .keepAlways
            add(attachment)
        }
        window.overrideUserInterfaceStyle = .unspecified

        try driver.calendar.setSelection([days[4]])
        driver.calendar.reloadData(); driver.view.layoutIfNeeded()
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner,
                                        .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                driver.view.layoutIfNeeded()
                return cells(in: driver.view).compactMap { $0 as? ConnectedRangeSwiftCell }.first {
                    $0.dayState?.occurrence.day == days[4] && $0.dayState?.occurrence.position == .current
                }?.selectionBackground.layer.maskedCorners == allCorners
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 3), .completed)
        let single = try band(20)
        XCTAssertEqual(single.selectionBackground.layer.maskedCorners, allCorners)
        let old = try XCTUnwrap(cells(in: driver.view).first {
            $0.dayState?.occurrence.day == days[0] && $0.dayState?.occurrence.position == .current
        })
        XCTAssertFalse(old.dayState?.isSelected ?? true)
        XCTAssertLessThan(old.selectionBackground.frame.width, old.contentView.bounds.width)
    }
    @MainActor func testConnectedRangeUsesButtonOnlyScopeAndContinuousViewport() throws {
        let list = ScenarioListController()
        list.loadViewIfNeeded()
        XCTAssertEqual(list.tableView.numberOfSections, 2)
        XCTAssertEqual(list.tableView(list.tableView, titleForHeaderInSection: 1), "Combined usage")
        XCTAssertEqual(list.tableView.numberOfRows(inSection: 1), 1)
        XCTAssertEqual(list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: 1)).accessibilityIdentifier,
                       "scenario.connectedRange")
        let window = (UIApplication.shared.delegate as! AppDelegate).showcaseWindow!
        let originalRoot = window.rootViewController
        defer {
            window.rootViewController = originalRoot
            window.makeKeyAndVisible()
        }
        let page = ScenarioController(scenario: .connectedRange)
        let navigation = UINavigationController(rootViewController: page)
        window.rootViewController = navigation; window.makeKeyAndVisible()
        page.view.layoutIfNeeded()
        let driver = try XCTUnwrap(page.driver as? SwiftCalendarDriver)
        XCTAssertEqual(driver.calendar.displayMode, .continuousMonths)
        XCTAssertFalse(driver.calendar.scopeGestureEnabled)
        XCTAssertEqual(driver.view.bounds.height, 400, accuracy: 0.5)
        let selected = DemoFixtures.date("2024-02-14")
        driver.select(selected)
        func waitForMode(_ mode: CalendarDisplayMode) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { driver.calendar.displayMode == mode }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            page.view.layoutIfNeeded()
        }
        driver.toggleScope(); waitForMode(.week)
        XCTAssertEqual(driver.view.bounds.height, driver.calendar.preferredHeight, accuracy: 0.5)
        XCTAssertEqual(driver.state.selection, [selected])
        driver.toggleScope(); waitForMode(.continuousMonths)
        XCTAssertEqual(driver.view.bounds.height, 400, accuracy: 0.5)
        XCTAssertEqual(driver.state.selection, [selected])
        driver.reset()
        XCTAssertEqual(driver.calendar.displayMode, .continuousMonths)
        XCTAssertTrue(driver.state.selection.isEmpty)
        XCTAssertEqual(driver.view.bounds.height, 400, accuracy: 0.5)
    }
    @MainActor func testConnectedRangeBlurChromeAndAgendaInsets() throws {
        let window = (UIApplication.shared.delegate as! AppDelegate).showcaseWindow!
        let originalRoot = window.rootViewController
        defer { window.rootViewController = originalRoot; window.makeKeyAndVisible() }
        let page = ScenarioController(scenario: .connectedRange)
        let navigation = UINavigationController(rootViewController: page)
        window.rootViewController = navigation; window.makeKeyAndVisible()
        navigation.view.layoutIfNeeded(); page.view.layoutIfNeeded()
        let driver = try XCTUnwrap(page.driver as? SwiftCalendarDriver)
        let calendar = driver.calendar
        let chrome = try XCTUnwrap(page.view.subviews.compactMap { $0 as? ConnectedRangeChromeView }.first)
        let agenda = try XCTUnwrap(page.view.subviews.compactMap { $0 as? UITableView }.first)
        XCTAssertTrue(calendar.isDescendant(of: chrome.contentView))
        XCTAssertFalse(calendar.isDescendant(of: chrome.scrollEdgeContainerView))
        XCTAssertEqual(chrome.alpha, 1)
        XCTAssertEqual(chrome.contentView.alpha, 1)
        XCTAssertFalse(chrome.scrollEdgeContainerView.isUserInteractionEnabled)
        XCTAssertTrue(chrome.scrollEdgeContainerView.accessibilityElementsHidden)
        XCTAssertEqual(calendar.appearance.backgroundColor, .clear)
        XCTAssertEqual(calendar.appearance.monthSeparatorCornerRadius, 8)
        let alternate = try XCTUnwrap(calendar.appearance.alternatingMonthBackgroundColor)
        for (style, expectedWhite, expectedAlpha): (UIUserInterfaceStyle, CGFloat, CGFloat) in [(.light, 0, 0.04), (.dark, 1, 0.06)] {
            var white: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(alternate.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getWhite(&white, alpha: &alpha))
            XCTAssertEqual(white, expectedWhite, accuracy: 0.001)
            XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.001)
        }
        XCTAssertNotEqual(SwiftCalendarDriver(scenario: .continuous).calendar.appearance.backgroundColor, .clear)
        if #available(iOS 26.0, *) {
            XCTAssertNil(chrome.effect)
            let interaction = try XCTUnwrap(chrome.scrollEdgeContainerView.interactions.compactMap {
                $0 as? UIScrollEdgeElementContainerInteraction
            }.first)
            XCTAssertTrue(interaction.scrollView === agenda)
            XCTAssertEqual(interaction.edge, .top)
            XCTAssertEqual(agenda.topEdgeEffect.style, .hard)
        } else {
            XCTAssertTrue(chrome.effect is UIBlurEffect)
            XCTAssertTrue(chrome.scrollEdgeContainerView.interactions.isEmpty)
        }
        XCTAssertEqual(agenda.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(agenda.contentOffset.y + agenda.contentInset.top, 0, accuracy: 0.5)
        let position: CGFloat = 123.25
        agenda.setContentOffset(CGPoint(x: 0, y: position - agenda.contentInset.top), animated: false)
        let originalPage = calendar.currentPage
        let boundary = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
        try calendar.setSelection(boundary)
        page.view.layoutIfNeeded()
        XCTAssertEqual(calendar.currentPage, originalPage)
        func checkInsets() {
            XCTAssertEqual(agenda.contentInset.top, chrome.frame.maxY, accuracy: 0.5)
            XCTAssertEqual(agenda.verticalScrollIndicatorInsets.top, agenda.contentInset.top, accuracy: 0.5)
            XCTAssertEqual(agenda.contentOffset.y + agenda.contentInset.top, position, accuracy: 0.5)
            XCTAssertEqual(chrome.scrollEdgeContainerView.bounds.width, chrome.contentView.bounds.width, accuracy: 0.001)
            XCTAssertEqual(chrome.scrollEdgeContainerView.bounds.height, chrome.contentView.bounds.height, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(agenda.bounds.height - chrome.frame.maxY - page.view.safeAreaInsets.bottom, 79.5)
        }
        checkInsets()
        calendar.reduceMotionOverride = true
        for mode: CalendarDisplayMode in [.week, .continuousMonths] {
            driver.toggleScope(); page.view.layoutIfNeeded()
            XCTAssertEqual(calendar.displayMode, mode)
            XCTAssertEqual(calendar.selectedDays, boundary)
            checkInsets()
        }
        // Also exercise a short, wide viewport and return to the original layout.
        let originalSize = navigation.view.bounds.size
        navigation.view.frame.size = CGSize(width: 700, height: 390)
        navigation.view.setNeedsLayout(); navigation.view.layoutIfNeeded(); page.view.layoutIfNeeded()
        checkInsets()
        XCTAssertGreaterThan(calendar.bounds.height, 0)
        XCTAssertLessThan(calendar.bounds.height, 400)
        navigation.view.frame.size = originalSize
        navigation.view.setNeedsLayout(); navigation.view.layoutIfNeeded(); page.view.layoutIfNeeded()
        checkInsets()
        driver.reset(); page.view.layoutIfNeeded()
        XCTAssertTrue(calendar.selectedDays.isEmpty)
        XCTAssertEqual(calendar.displayMode, .continuousMonths)
        checkInsets()
    }

    @MainActor func testConnectedRangeScopePresentationFramesStayOnOneTimeline() throws {
        let window = (UIApplication.shared.delegate as! AppDelegate).showcaseWindow!
        let originalRoot = window.rootViewController
        defer { window.rootViewController = originalRoot; window.overrideUserInterfaceStyle = .unspecified; window.makeKeyAndVisible() }
        let page = ScenarioController(scenario: .connectedRange)
        window.rootViewController = UINavigationController(rootViewController: page)
        window.makeKeyAndVisible(); page.view.layoutIfNeeded()
        let driver = try XCTUnwrap(page.driver as? SwiftCalendarDriver)
        let calendar = driver.calendar
        let chrome = try XCTUnwrap(page.view.subviews.compactMap { $0 as? ConnectedRangeChromeView }.first)
        let agenda = try XCTUnwrap(page.view.subviews.compactMap { $0 as? UITableView }.first)
        let agendaPosition: CGFloat = 137.25
        agenda.setContentOffset(CGPoint(x: 0, y: agendaPosition - agenda.contentInset.top), animated: false)
        calendar.reduceMotionOverride = false
        let boundary = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
        try calendar.setSelection(boundary)
        func waitForFrame(_ description: String, _ condition: @escaping @MainActor () -> Bool) {
            let ready = expectation(description: description)
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
                if MainActor.assumeIsolated({ condition() }) { timer.invalidate(); ready.fulfill() }
            }
            defer { timer.invalidate() }
            wait(for: [ready], timeout: 3)
        }
        let pixel = 1 / calendar.traitCollection.displayScale
        for style: UIUserInterfaceStyle in [.light, .dark] {
            window.overrideUserInterfaceStyle = style
            page.view.layoutIfNeeded()
            waitForFrame("Initial continuous viewport is displayed") {
                abs((calendar.layer.presentation()?.bounds.height ?? 0) - 400) <= pixel
            }
            // Keep a fractional scroll position to catch a preparation-time page snap.
            calendar.collectionView.contentOffset.y += 11.25
            for target: CalendarDisplayMode in [.week, .continuousMonths] {
                let beforeHeight = calendar.layer.presentation()?.bounds.height ?? calendar.bounds.height
                driver.toggleScope()
                let context = try XCTUnwrap(calendar.transition)
                let animator = try XCTUnwrap(context.animator)
                XCTAssertEqual(animator.duration, 0.3)
                animator.pauseAnimation()
                var trace: [[String: Double]] = []
                for fraction: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                    animator.fractionComplete = fraction
                    let expected = context.sourceHeight + (context.targetHeight - context.sourceHeight) * fraction
                    waitForFrame("Scope frame \(fraction) is displayed") {
                        abs((calendar.layer.presentation()?.bounds.height ?? 0) - expected) <= pixel
                    }
                    let height = try XCTUnwrap(calendar.layer.presentation()).bounds.height
                    let chromeBottom = try XCTUnwrap(chrome.layer.presentation()).frame.maxY
                    let agendaOffset = try XCTUnwrap(agenda.layer.presentation()).bounds.minY
                    XCTAssertEqual(chromeBottom + agendaOffset, agendaPosition, accuracy: pixel)
                    XCTAssertEqual(chrome.layer.presentation()?.opacity, 1)
                    let header = try XCTUnwrap(calendar.weekdayStack.layer.presentation()).frame.minY
                    let monthFraction = target.isContinuous ? fraction : 1 - fraction
                    XCTAssertEqual(header, calendar.effectiveHeaderHeight * (1 - monthFraction), accuracy: pixel)
                    if fraction == 0 { XCTAssertEqual(height, beforeHeight, accuracy: pixel) }
                    for day in boundary {
                        let cell = try XCTUnwrap(calendar.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }
                            .first { $0.dayState?.occurrence.day == day })
                        XCTAssertEqual(cell.layer.presentation()?.opacity, 1)
                    }
                    for cell in calendar.collectionView.visibleCells {
                        let index = try XCTUnwrap(calendar.collectionView.indexPath(for: cell))
                        let row = (calendar.calendarLayout.continuousSections[index.section].startSlot + index.item) / 7
                        if row != context.focusedRow {
                            XCTAssertEqual(Double(cell.layer.presentation()?.opacity ?? -1), Double(monthFraction), accuracy: 0.01)
                        }
                    }
                    XCTAssertLessThanOrEqual(try XCTUnwrap(calendar.titleLabel.layer.presentation()).frame.maxY, header + pixel)
                    trace.append(["fraction": Double(fraction), "height": Double(height), "header": Double(header)])
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: false))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "scope-\(style == .dark ? "dark" : "light")-\(target.isContinuous ? "expand" : "collapse")-\(Int(fraction * 100))"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
                let lastHeight = try XCTUnwrap(calendar.layer.presentation()).bounds.height
                animator.stopAnimation(false); animator.finishAnimation(at: .end)
                page.view.layoutIfNeeded()
                XCTAssertEqual(calendar.transitionState, .idle)
                XCTAssertEqual(calendar.displayMode, target)
                XCTAssertEqual(calendar.bounds.height, lastHeight, accuracy: pixel)
                XCTAssertEqual(calendar.selectedDays, boundary)
                XCTAssertTrue(context.titleFades.allSatisfy { $0.outgoing.superview == nil })
                let data = try JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys])
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "scope-presentation-\(style.rawValue)-\(target.scope.rawValue)"; attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        calendar.reduceMotionOverride = true
        driver.toggleScope()
        XCTAssertEqual(calendar.transitionState, .idle)
        XCTAssertEqual(calendar.displayMode, .week)
        driver.toggleScope()
        XCTAssertEqual(calendar.transitionState, .idle)
        XCTAssertEqual(calendar.bounds.height, 400, accuracy: pixel)
    }

    @MainActor func testSwiftRepeatedNavigationPerformance() {
        let driver = SwiftCalendarDriver(scenario: .month)
        let window = host(driver); defer { window.isHidden = true }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for month in 1...12 {
                try! driver.calendar.setCurrentPage(DemoFixtures.date(String(format: "2024-%02d-01", month)), animated: false)
                driver.view.layoutIfNeeded()
            }
        }
    }
    @MainActor func testSwiftCustomContentAndCellReuse() throws {
        let driver = SwiftCalendarDriver(scenario: .content)
        let window = host(driver); defer { window.isHidden = true }
        for month in ["2024-08-01", "2024-02-01"] {
            try driver.calendar.setCurrentPage(DemoFixtures.date(month))
            driver.view.layoutIfNeeded()
        }
        func cells(in view: UIView) -> [FSCalendarCell] {
            (view as? FSCalendarCell).map { [$0] } ?? view.subviews.flatMap(cells)
        }
        let visible = cells(in: driver.view)
        let first = try XCTUnwrap(visible.first { $0.dayState?.occurrence.day.day == 1 && $0.dayState?.occurrence.position == .current })
        XCTAssertEqual(first.titleLabel.text, "1st")
        let heartDay = try CivilDay(year: 2024, month: 2, day: 14)
        let heart = try XCTUnwrap(visible.first { $0.dayState?.occurrence.day == heartDay })
        XCTAssertNotNil(heart.dayImageView.image)
        heart.layoutIfNeeded()
        XCTAssertFalse(heart.dayImageView.frame.intersects(heart.subtitleLabel.frame))
        XCTAssertFalse(heart.dayImageView.frame.intersects(heart.titleLabel.frame))
        XCTAssertEqual(heart.subtitleLabel.text, DemoFixtures.lunarSubtitle(DemoFixtures.initialDate))
        XCTAssertTrue(heart.accessibilityValue?.contains("2 events") == true)
        let neighborDay = try CivilDay(year: 2024, month: 2, day: 15)
        let neighbor = try XCTUnwrap(visible.first { $0.dayState?.occurrence.day == neighborDay })
        XCTAssertNil(neighbor.dayImageView.image)
    }
}

@MainActor private final class AppearanceController: UIViewController {
    var onAppear: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}
