import AppKit
import XCTest
import FSCalendarCore
import CalendarDemoSupportMac
@testable import FSCalendarAppKit

final class MacPerformanceTests: XCTestCase {
    @MainActor func testNavigationAndMemoryMeasurements() throws {
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 630, height: 334))
        try view.apply(configuration: CalendarConfiguration(
            minimumDate: CivilDay(date: DemoFixtures.minimumDate, timeZone: DemoFixtures.calendar.timeZone),
            maximumDate: CivilDay(date: DemoFixtures.maximumDate, timeZone: DemoFixtures.calendar.timeZone),
            timeZone: DemoFixtures.calendar.timeZone, locale: DemoFixtures.calendar.locale!))
        view.today = try CivilDay(date: DemoFixtures.initialDate, timeZone: DemoFixtures.calendar.timeZone)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        let initial = try CivilDay(year: 2024, month: 2, day: 14)
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            try! view.setCurrentPage(initial)
            for _ in 0..<24 { try! view.navigate(1, animated: false); view.layoutSubtreeIfNeeded() }
            for _ in 0..<24 { try! view.navigate(-1, animated: false); view.layoutSubtreeIfNeeded() }
        }
        XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
    }
    @MainActor func testContinuousScrollingMeasurements() throws {
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 630, height: 420))
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
        try view.apply(configuration: CalendarConfiguration(
            minimumDate: CivilDay(date: DemoFixtures.minimumDate, timeZone: DemoFixtures.calendar.timeZone),
            maximumDate: CivilDay(date: DemoFixtures.maximumDate, timeZone: DemoFixtures.calendar.timeZone),
            timeZone: DemoFixtures.calendar.timeZone, locale: DemoFixtures.calendar.locale!))
        view.today = try CivilDay(date: DemoFixtures.initialDate, timeZone: DemoFixtures.calendar.timeZone)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            try! view.setDisplayMode(.continuousMonths, animated: false)
            try! view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
            let start = view.scrollView.contentView.bounds.origin
            for index in 0..<100 {
                view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: start.y + CGFloat(index * 12)))
                view.collectionView.layoutSubtreeIfNeeded()
            }
        }
        XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
    }
    @MainActor func testInteractiveTransitionMeasurements() throws {
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 630, height: 334))
        try view.apply(configuration: CalendarConfiguration(
            minimumDate: CivilDay(date: DemoFixtures.minimumDate, timeZone: DemoFixtures.calendar.timeZone),
            maximumDate: CivilDay(date: DemoFixtures.maximumDate, timeZone: DemoFixtures.calendar.timeZone),
            timeZone: DemoFixtures.calendar.timeZone, locale: DemoFixtures.calendar.locale!))
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
        view.today = try CivilDay(date: DemoFixtures.initialDate, timeZone: DemoFixtures.calendar.timeZone)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            for _ in 0..<10 {
                try! view.beginInteractiveTransition(to: .week)
                for step in 0...10 { view.updateInteractiveTransition(progress: CGFloat(step) / 10) }
                view.finishInteractiveTransition(commit: true, animated: false)
                try! view.setDisplayMode(.month(.horizontal), animated: false)
            }
        }
        XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
    }
}
