#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit

@MainActor private final class TransitionSpy: FSCalendarDelegate {
    var completion: (() -> Void)?
    var modes: [CalendarDisplayMode] = []
    var pages: [CivilDay] = []
    func calendar(_ calendar: FSCalendarView, didChangeDisplayMode mode: CalendarDisplayMode) { modes.append(mode); completion?() }
    func calendarCurrentPageDidChange(_ calendar: FSCalendarView) { pages.append(calendar.currentPage) }
}
final class CalendarTransitionTests: XCTestCase {
    @MainActor private func make() throws -> FSCalendarView {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 334))
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!))
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14))
        view.layoutSubtreeIfNeeded(); return view
    }
    @MainActor func testInteractiveCommitCancellationAndAnchor() throws {
        let view = try make(), spy = TransitionSpy(); view.delegate = spy
        let day = try CivilDay(year: 2024, month: 2, day: 22)
        try view.select(day)
        let page = view.currentPage, height = view.preferredHeight
        try view.beginInteractiveTransition(to: .week); view.updateInteractiveTransition(progress: 0.6)
        XCTAssertEqual(view.transitionState, .interactive)
        XCTAssertEqual(view.displayMode, .month(.horizontal)); XCTAssertEqual(view.currentPage, page)
        XCTAssertLessThan(view.preferredHeight, height)
        view.finishInteractiveTransition(commit: false, animated: false)
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.currentPage, page)
        XCTAssertEqual(view.preferredHeight, height); XCTAssertTrue(spy.modes.isEmpty)
        try view.beginInteractiveTransition(to: .week); view.updateInteractiveTransition(progress: 1)
        view.finishInteractiveTransition(commit: true, animated: false)
        XCTAssertEqual(view.displayMode, .week)
        XCTAssertEqual(view.currentPage, view.engine.pageID(containing: day, scope: .week).anchor)
        XCTAssertEqual(spy.modes, [.week]); XCTAssertEqual(spy.pages.count, 1)
    }
    @MainActor func testResizeConfigurationReplacementAndRepeatedModes() throws {
        let view = try make()
        let page = view.currentPage
        try view.beginInteractiveTransition(to: .week); view.updateInteractiveTransition(progress: 0.5)
        view.frame.size.width += 70; view.needsLayout = true; view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.currentPage, page)
        try view.beginInteractiveTransition(to: .week)
        try view.apply(configuration: CalendarConfiguration(firstWeekday: 2))
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.displayMode, .month(.horizontal))
        try view.beginInteractiveTransition(to: .week)
        try view.setDisplayMode(.month(.vertical), animated: false)
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.displayMode, .month(.vertical))
        for _ in 0..<20 {
            try view.setDisplayMode(.week, animated: false)
            try view.setDisplayMode(.month(.horizontal), animated: false)
        }
        XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
        XCTAssertThrowsError(try view.beginInteractiveTransition(to: .continuousMonths))
    }
    @MainActor func testAnimatedReplacementSettlesOnlyLatestRequest() async throws {
        let view = try make(), spy = TransitionSpy(); view.delegate = spy; view.reduceMotionOverride = false
        let finished = expectation(description: "latest transition finishes")
        spy.completion = { finished.fulfill() }
        try view.setDisplayMode(.week, animated: true)
        XCTAssertEqual(view.transitionState, .settling); XCTAssertEqual(view.displayMode, .month(.horizontal))
        try view.setDisplayMode(.month(.vertical), animated: true)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(spy.modes, [.month(.vertical)])
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.displayMode, .month(.vertical))
    }
    @MainActor func testReduceMotionCompletesWithoutSettlingAnimation() throws {
        let view = try make(); view.reduceMotionOverride = true
        try view.setDisplayMode(.week, animated: true)
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.displayMode, .week)
        try view.beginInteractiveTransition(to: .month(.horizontal))
        view.updateInteractiveTransition(progress: .nan)
        XCTAssertTrue(view.preferredHeight.isFinite)
        view.finishInteractiveTransition(commit: true)
        XCTAssertEqual(view.transitionState, .idle); XCTAssertEqual(view.displayMode, .month(.horizontal))
    }
}
#endif
