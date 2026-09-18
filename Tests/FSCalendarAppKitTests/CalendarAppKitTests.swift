#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit

final class CalendarAppKitTests: XCTestCase {
    @MainActor func testProgrammaticInitialization() {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
        XCTAssertEqual(view.frame.width, 480)
    }

    @MainActor func testRealMonthGridNavigationAndPlaceholders() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX")))
        try view.setCurrentPage(day)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        view.layoutSubtreeIfNeeded(); view.collectionView.layoutSubtreeIfNeeded()
        let items = view.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }
        XCTAssertEqual(items.count, 42)
        XCTAssertTrue(items.contains { $0.dayState?.occurrence.day == day })
        XCTAssertEqual(view.titleLabel.stringValue, "February 2024")
        XCTAssertEqual(view.weekdayLabels.first?.accessibilityLabel(), "Sunday")
        try view.navigate(1, animated: false)
        XCTAssertEqual(view.currentPage, try CivilDay(year: 2024, month: 3, day: 1))
        try view.navigate(-1, animated: false)
        XCTAssertEqual(view.currentPage, day.startOfMonth)
    }
    @MainActor func testBoundsFirstWeekdayHiddenAndVariableHeight() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let minimum = try CivilDay(year: 2024, month: 2, day: 10)
        let maximum = try CivilDay(year: 2024, month: 3, day: 20)
        try view.apply(configuration: CalendarConfiguration(firstWeekday: 2, placeholders: .none,
            minimumDate: minimum, maximumDate: maximum, timeZone: TimeZone(secondsFromGMT: 0)!))
        try view.setCurrentPage(minimum)
        let grid = try XCTUnwrap(view.controller.grid(0))
        XCTAssertTrue(grid.occurrences.filter { $0.position != .current }.allSatisfy(\.isHidden))
        XCTAssertFalse(grid.occurrences.first { $0.day.day == 9 && $0.position == .current }!.isSelectable)
        XCTAssertEqual(grid.rowCount, 5)
        XCTAssertEqual(view.intrinsicContentSize.height, view.preferredHeight)
        XCTAssertThrowsError(try view.navigate(-1))
        XCTAssertEqual(view.currentPage, minimum.startOfMonth)
    }
}
#endif
