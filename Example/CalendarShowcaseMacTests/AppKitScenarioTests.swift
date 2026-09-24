import AppKit
import XCTest
import FSCalendarCore
import FSCalendarAppKit
import CalendarDemoSupportMac
@testable import CalendarShowcaseMac

final class AppKitScenarioTests: XCTestCase {
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
}
