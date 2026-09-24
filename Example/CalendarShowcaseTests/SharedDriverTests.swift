import CalendarDemoSupport
import UIKit
import XCTest
import FSCalendarCore
import FSCalendar
@testable import CalendarShowcase

final class SharedDriverTests: XCTestCase {
    @MainActor private func makeWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return window
    }

    @MainActor func testNavigationKeepsInitialCalendarHeight() {
        let window = (UIApplication.shared.delegate as! AppDelegate).window!
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
    @MainActor func testConnectedRangeBandGeometryAndReuse() throws {
        let driver = SwiftCalendarDriver(scenario: .connectedRange)
        let window = host(driver); defer { window.isHidden = true }
        let days = try (16...20).map { try CivilDay(date: DemoFixtures.date("2024-02-\($0)"), timeZone: DemoFixtures.calendar.timeZone) }
        try driver.calendar.setSelection(days)
        driver.calendar.reloadData(); driver.view.layoutIfNeeded()
        func cells(in view: UIView) -> [FSCalendarCell] {
            (view as? FSCalendarCell).map { [$0] } ?? view.subviews.flatMap(cells)
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
        let window = (UIApplication.shared.delegate as! AppDelegate).window!
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
