#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit

final class CalendarLayoutTests: XCTestCase {
    @MainActor func testAllModesNavigationResizingAndNinePageCache() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let initial = try CivilDay(year: 2024, month: 2, day: 14)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        for mode: CalendarDisplayMode in [.month(.horizontal), .month(.vertical), .week, .continuousMonths] {
            try view.setDisplayMode(mode, animated: false); try view.setCurrentPage(initial)
            let original = view.currentPage
            for _ in 0..<24 { try view.navigate(1, animated: false); view.layoutSubtreeIfNeeded() }
            for _ in 0..<24 { try view.navigate(-1, animated: false); view.layoutSubtreeIfNeeded() }
            XCTAssertEqual(view.currentPage, original)
            XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
            XCTAssertGreaterThan(view.cachedPageCount, 0)
            window.setContentSize(NSSize(width: 630, height: 410)); view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.currentPage, original)
            let section = view.calendarLayout.section(at: view.scrollView.contentView.bounds.origin)
            XCTAssertEqual(try view.engine.page(at: section, scope: mode.scope).anchor, original)
        }
    }
    @MainActor func testStickyHeadersRTLAndPagedScrollSettling() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        try view.setCurrentPage(day); view.layoutSubtreeIfNeeded()
        view.input.accumulateScroll(-20, ended: false)
        view.input.accumulateScroll(-25, ended: false)
        XCTAssertEqual(view.currentPage, day.startOfMonth)
        view.input.accumulateScroll(-25, ended: true)
        XCTAssertEqual(view.currentPage, try CivilDay(year: 2024, month: 3, day: 1))
        view.userInterfaceLayoutDirection = .rightToLeft
        view.needsLayout = true; view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.weekdayLabels.first?.accessibilityLabel(), "Saturday")
        let section = try view.engine.sectionIndex(for: view.currentPage, scope: .month)
        let a = try XCTUnwrap(view.calendarLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)))
        XCTAssertEqual(a.frame.minX - view.calendarLayout.offset(for: section).x, 420, accuracy: 0.1)
        try view.setDisplayMode(.continuousMonths, animated: false)
        let start = view.calendarLayout.offset(for: section)
        view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: start.y + 70))
        let header = try XCTUnwrap(view.calendarLayout.layoutAttributesForSupplementaryView(ofKind: NSCollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)))
        XCTAssertEqual(header.frame.minY, start.y + 70, accuracy: 0.1)
        XCTAssertEqual(header.zIndex, 100)
        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }
}
#endif
