#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
#if SWIFT_PACKAGE
import CalendarContractSupport
#endif
import FSCalendarCore
@testable import FSCalendarAppKit

extension FSCalendarView: RendererSelectionContract {}
@MainActor final class MacCalendarSpy: FSCalendarDelegate {
    var changes: [SelectionChange] = []
    var allow = true
    var reentry = false
    var reentryError: CalendarError?
    func calendar(_ calendar: FSCalendarView, shouldApply change: SelectionChange) -> Bool {
        if reentry { do { try calendar.clearSelection() } catch { reentryError = error as? CalendarError } }
        return allow
    }
    func calendar(_ calendar: FSCalendarView, didChangeSelection change: SelectionChange) { changes.append(change) }
}
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
        let target = try XCTUnwrap(items.first { $0.dayState?.occurrence.day == day })
        let center = view.convert(NSPoint(x: target.view.bounds.midX, y: target.view.bounds.midY), from: target.view)
        XCTAssertTrue(view.hitTest(view.convert(center, to: view.superview)) === target.view, "Day center must hit its own input view")
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

    @MainActor func testSharedSelectionContract() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let spy = MacCalendarSpy(); view.delegate = spy
        try SharedRendererAssertions.verifySelection(view, changes: { spy.changes }, allow: { spy.allow = $0 })
    }
    @MainActor func testClickToggleDragPaintingFocusAndReentry() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        try view.apply(configuration: CalendarConfiguration(selectionMode: .multiple))
        let a = try CivilDay(year: 2024, month: 2, day: 14), b = try a.addingDays(1)
        let spy = MacCalendarSpy(); view.delegate = spy
        try view.focus(a); XCTAssertTrue(view.selectedDays.isEmpty)
        view.input.activate(a); view.input.activate(b); view.input.activate(a)
        XCTAssertEqual(view.selectedDays, [b])
        view.input.begin(a); view.input.visit(a); view.input.visit(b); view.input.end()
        XCTAssertEqual(view.selectedDays, [b, a])
        view.input.begin(b); view.input.visit(a); view.input.visit(b); view.input.end()
        XCTAssertTrue(view.selectedDays.isEmpty)
        spy.reentry = true; try view.select(a)
        XCTAssertEqual(spy.reentryError, .reentrantMutation)
        XCTAssertEqual(spy.changes.last?.selection, [a])
        view.input.moveFocus(7)
        XCTAssertEqual(view.focusedDay, try b.addingDays(7))
        XCTAssertEqual(view.selectedDays, [a])
    }
    @MainActor func testFocusPruningAndInvalidFocusDoNotSelect() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: .zero)
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        try view.focus(day)
        try view.apply(configuration: CalendarConfiguration(minimumDate: day.addingDays(1)))
        XCTAssertEqual(view.focusedDay, try day.addingDays(1))
        XCTAssertThrowsError(try view.focus(day))
        XCTAssertTrue(view.selectedDays.isEmpty)
    }
}
#endif
