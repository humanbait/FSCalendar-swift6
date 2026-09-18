import AppKit
import XCTest
import FSCalendarCore
import FSCalendarAppKit
import CalendarDemoSupportMac
@testable import CalendarShowcaseMac

final class AppKitScenarioTests: XCTestCase {
    @MainActor func testAllEighteenScenariosRenderNavigateSelectAndReset() throws {
        XCTAssertEqual(DemoScenario.allCases.count, 18)
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
}
