import CalendarDemoSupport
import UIKit
import XCTest
import FSCalendarCore
import FSCalendar
@testable import CalendarShowcase

final class SharedDriverTests: XCTestCase {
    @MainActor private func host(_ driver: any UIKitCalendarDemoDriver) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(driver.view)
        driver.view.frame = CGRect(x: 0, y: 50, width: 390, height: 320)
        window.makeKeyAndVisible(); driver.view.layoutIfNeeded(); driver.reset(); driver.view.layoutIfNeeded()
        return window
    }
    @MainActor func testEveryImplementationAndScenarioRendersTheFixture() {
        for implementation in DemoDriverFactory.implementations {
            for scenario in DemoScenario.allCases {
                let driver = DemoDriverFactory.make(implementation, scenario: scenario)
                let window = host(driver)
                defer { window.isHidden = true }
                XCTAssertEqual(driver.state.scope, scenario == .week ? "week" : "month", "\(implementation)/\(scenario)")
                XCTAssertTrue(DemoFixtures.text(driver.state.page).hasPrefix("2024-02"), "\(implementation)/\(scenario): \(driver.state.page)")
                XCTAssertTrue(driver.state.selection.isEmpty)
            }
        }
    }
    @MainActor func testSharedSelectionAndReloadPersistence() {
        for implementation in DemoDriverFactory.implementations {
            let driver = DemoDriverFactory.make(implementation, scenario: .multiple)
            let window = host(driver); defer { window.isHidden = true }
            let a = DemoFixtures.date("2024-02-12"), b = DemoFixtures.date("2024-02-14")
            driver.select(a); driver.select(b); driver.reloadContent(); driver.view.layoutIfNeeded()
            XCTAssertEqual(driver.state.selection, [a, b], implementation)
            driver.deselect(a)
            XCTAssertEqual(driver.state.selection, [b], implementation)
            driver.reset()
            XCTAssertTrue(driver.state.selection.isEmpty, implementation)
        }
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
