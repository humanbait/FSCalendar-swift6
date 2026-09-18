import CalendarDemoSupport
import XCTest
@testable import CalendarShowcase

final class LegacyDriverTests: XCTestCase {
    @MainActor
    private func host(_ driver: LegacyCalendarDriver) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(driver.view)
        driver.view.frame = CGRect(x: 0, y: 50, width: 390, height: 320)
        window.makeKeyAndVisible()
        driver.view.layoutIfNeeded()
        return window
    }
    @MainActor func testSingleSelectionReplacesPrevious() {
        let driver = LegacyCalendarDriver(scenario: .month)
        let window = host(driver)
        defer { window.isHidden = true }
        driver.select(DemoFixtures.date("2024-02-12"))
        driver.select(DemoFixtures.date("2024-02-14"))
        XCTAssertEqual(driver.state.selection.map(DemoFixtures.text), ["2024-02-14"])
    }
    @MainActor func testMultipleSelectionPreservesOrderAndDeduplicates() {
        let driver = LegacyCalendarDriver(scenario: .multiple)
        let window = host(driver)
        defer { window.isHidden = true }
        let a = DemoFixtures.date("2024-02-12"), b = DemoFixtures.date("2024-02-14")
        driver.select(b); driver.select(a); driver.select(b)
        XCTAssertEqual(driver.state.selection.map(DemoFixtures.text), ["2024-02-14", "2024-02-12"])
        driver.deselect(b)
        XCTAssertEqual(driver.state.selection, [a])
    }
    @MainActor func testLegacyProgrammaticSelectionDoesNotEmitSelectionDelegateCallback() {
        let driver = LegacyCalendarDriver(scenario: .month)
        let window = host(driver)
        defer { window.isHidden = true }
        driver.select(DemoFixtures.initialDate)
        XCTAssertFalse(driver.events.contains { $0.hasPrefix("selected") })
    }
    @MainActor func testResetClearsSelection() {
        let driver = LegacyCalendarDriver(scenario: .multiple)
        let window = host(driver)
        defer { window.isHidden = true }
        driver.select(DemoFixtures.initialDate)
        driver.reset()
        XCTAssertTrue(driver.state.selection.isEmpty)
    }
    @MainActor func testEveryScenarioCanLayoutAndReload() {
        for scenario in DemoScenario.allCases {
            let driver = LegacyCalendarDriver(scenario: scenario)
            let window = host(driver)
            driver.reloadContent()
            driver.view.layoutIfNeeded()
            XCTAssertFalse(driver.calendar.visibleCells().isEmpty, scenario.rawValue)
            window.isHidden = true
        }
    }
    @MainActor func testSelectionSurvivesReloadAndPageChange() {
        let driver = LegacyCalendarDriver(scenario: .multiple)
        let window = host(driver)
        defer { window.isHidden = true }
        driver.select(DemoFixtures.initialDate)
        driver.calendar.setCurrentPage(DemoFixtures.date("2024-03-01"), animated: false)
        driver.reloadContent()
        XCTAssertEqual(driver.state.selection, [DemoFixtures.initialDate])
    }
    @MainActor func testRepeatedNavigationPerformance() {
        let driver = LegacyCalendarDriver(scenario: .month)
        let window = host(driver)
        defer { window.isHidden = true }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for month in 1...12 {
                driver.calendar.setCurrentPage(DemoFixtures.date(String(format: "2024-%02d-01", month)), animated: false)
                driver.view.layoutIfNeeded()
            }
        }
    }
    @MainActor func testSelectedDayIsSynchronizedIntoNextMonthsPlaceholder() throws {
        let driver = LegacyCalendarDriver(scenario: .multiple)
        let window = host(driver)
        defer { window.isHidden = true }
        let date = DemoFixtures.date("2024-02-29")
        driver.select(date)
        let original = try XCTUnwrap(driver.calendar.cell(for: date, at: .current))
        XCTAssertTrue(original.isSelected)
        let originalIdentifier = original.accessibilityIdentifier
        driver.calendar.setCurrentPage(DemoFixtures.date("2024-03-01"), animated: false)
        driver.view.layoutIfNeeded()
        let placeholder = try XCTUnwrap(driver.calendar.cell(for: date, at: .previous))
        XCTAssertTrue(placeholder.isSelected)
        XCTAssertNotEqual(placeholder.accessibilityIdentifier, originalIdentifier)
        driver.deselect(date)
        XCTAssertFalse(placeholder.isSelected)
        XCTAssertTrue(driver.state.selection.isEmpty)
    }
    @MainActor func testCustomContentSurvivesCellReuse() throws {
        let driver = LegacyCalendarDriver(scenario: .content)
        let window = host(driver)
        defer { window.isHidden = true }
        let date = DemoFixtures.initialDate
        for month in ["2024-02-01", "2024-08-01", "2024-02-01"] {
            driver.calendar.setCurrentPage(DemoFixtures.date(month), animated: false)
            driver.view.layoutIfNeeded()
        }
        let cell = try XCTUnwrap(driver.calendar.cell(for: date, at: .current))
        XCTAssertEqual(cell.titleLabel.text, "14")
        XCTAssertEqual(cell.subtitleLabel.text, DemoFixtures.lunarSubtitle(date))
        XCTAssertEqual(cell.numberOfEvents, 2)
        XCTAssertNotNil(cell.imageView.image)
        let neighbor = try XCTUnwrap(driver.calendar.cell(for: DemoFixtures.date("2024-02-15"), at: .current))
        XCTAssertNil(neighbor.imageView.image)
        XCTAssertEqual(neighbor.numberOfEvents, 3)
    }
    @MainActor func testCustomCellClassSurvivesRepeatedNavigation() throws {
        let driver = LegacyCalendarDriver(scenario: .custom)
        let window = host(driver)
        defer { window.isHidden = true }
        for month in 1...12 {
            driver.calendar.setCurrentPage(DemoFixtures.date(String(format: "2024-%02d-01", month)), animated: false)
            driver.view.layoutIfNeeded()
            let cells = driver.calendar.visibleCells()
            XCTAssertFalse(cells.isEmpty)
            XCTAssertTrue(cells.allSatisfy { $0 is DemoLegacyCell })
        }
    }
}
