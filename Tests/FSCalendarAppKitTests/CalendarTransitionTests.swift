#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit

@MainActor private final class TransitionSpy: FSCalendarDelegate {
    var completion: (() -> Void)?
    var heightChanged: ((CGFloat) -> Void)?
    func calendar(_ calendar: FSCalendarView, preferredHeightDidChange height: CGFloat, animated: Bool) { heightChanged?(height) }
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
    @MainActor func testContinuousBoundaryGeometryAtEveryQuarterAndMatchingEndpoints() throws {
        for rtl in [false, true] {
            for anchor in [try CivilDay(year: 2024, month: 3, day: 1), try CivilDay(year: 2025, month: 1, day: 1)] {
                let view = try make(), spy = TransitionSpy()
                view.referenceDate = { Date(timeIntervalSince1970: 1767225600) }
                try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!,
                    locale: Locale(identifier: "en_US_POSIX"), selectionMode: .multiple))
                var appearance = view.calendarAppearance; appearance.rowHeight = 47.25
                view.calendarAppearance = appearance
                view.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                try view.setDisplayMode(.continuousMonths, animated: false)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700.5, height: 600),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let host = NSView(frame: window.contentView!.bounds)
                window.contentView = host; host.addSubview(view)
                view.frame = NSRect(x: 0, y: 0, width: 700.5, height: 420)
                window.orderFront(nil)
                defer { window.close() }
                spy.heightChanged = { [weak view] height in view?.frame.size.height = height }
                view.delegate = spy
                let previous = try anchor.addingDays(-1)
                try view.setSelection([previous, anchor]); try view.setCurrentPage(previous)
                view.frame.size.height = 420; view.needsLayout = true; view.layoutSubtreeIfNeeded()
                var offset = view.scrollView.contentView.bounds.origin; offset.y += 13.25
                view.scrollView.contentView.scroll(to: offset)
                view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
                view.collectionView.layoutSubtreeIfNeeded()
                func cell(_ day: CivilDay) throws -> FSCalendarItem {
                    try XCTUnwrap(view.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }.first {
                        $0.dayState?.occurrence.day == day
                    })
                }
                func frame(_ day: CivilDay) throws -> NSRect {
                    let item = try cell(day); return item.view.convert(item.view.bounds, to: view)
                }
                let pixel = 1 / window.backingScaleFactor
                for target: CalendarDisplayMode in [.week, .continuousMonths] {
                    let before = try frame(anchor)
                    view.prepareTransition(to: target)
                    let context = try XCTUnwrap(view.transition)
                    XCTAssertTrue(context.isContinuousScope)
                    XCTAssertEqual(try frame(anchor).minY, before.minY, accuracy: pixel)
                    XCTAssertEqual(context.targetHeight, target == .week ? view.height(for: anchor, mode: .week) : 420)
                    for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                        view.updateInteractiveTransition(progress: progress)
                        let height = context.sourceHeight + (context.targetHeight - context.sourceHeight) * progress
                        XCTAssertEqual(view.bounds.height, height, accuracy: pixel)
                        XCTAssertEqual(view.titleLabel.frame.maxY, view.weekdayLabels[0].frame.minY, accuracy: pixel)
                        XCTAssertEqual(view.scrollView.frame.minY, view.weekdayLabels[0].frame.maxY, accuracy: pixel)
                        view.reload(dates: Set([previous, anchor]))
                        for fade in context.titleFades {
                            XCTAssertEqual(fade.label.alphaValue, progress, accuracy: 0.001)
                            XCTAssertEqual(fade.outgoing.alphaValue, 1 - progress, accuracy: 0.001)
                        }
                        let expectedY = view.scrollView.frame.minY + context.rowOffset * context.monthProgress
                        XCTAssertEqual(try frame(anchor).minY, expectedY, accuracy: pixel)
                        XCTAssertEqual(try frame(previous).minY, try frame(anchor).minY, accuracy: pixel)
                        XCTAssertEqual(try cell(anchor).view.alphaValue, 1, accuracy: 0.01)
                        let content = try cell(anchor)
                        content.view.layoutSubtreeIfNeeded()
                        XCTAssertEqual(content.subtitleLabel.alphaValue, context.monthProgress, accuracy: 0.001)
                        XCTAssertEqual(content.subtitleLabel.stringValue, String(anchor.year))
                        XCTAssertEqual(content.selectionBackground.frame.midY,
                            content.view.bounds.height * (5 + context.monthProgress) / 12, accuracy: 0.001)
                        XCTAssertEqual(content.titleLabel.frame.midY + content.subtitleLabel.frame.height * context.monthProgress / 2,
                            content.selectionBackground.frame.midY, accuracy: 0.001)
                        XCTAssertEqual(try cell(previous).view.alphaValue, 1, accuracy: 0.01)
                        let attributes = view.calendarLayout.layoutAttributesForElements(in: view.collectionView.visibleRect)
                        for attribute in attributes where attribute.representedElementCategory == .item {
                            let index = try XCTUnwrap(attribute.indexPath)
                            let slot = view.calendarLayout.continuousSections[index.section].startSlot + index.item
                            XCTAssertEqual(attribute.alpha, slot / 7 == context.focusedRow ? 1 : context.monthProgress, accuracy: 0.001)
                            if let item = view.collectionView.item(at: index), item.view.frame.intersects(view.collectionView.visibleRect) {
                                XCTAssertEqual(item.view.alphaValue, attribute.alpha, accuracy: 0.01)
                            }
                        }
                        for attribute in attributes where attribute.representedElementCategory == .decorationView {
                            XCTAssertEqual(attribute.alpha, context.monthProgress, accuracy: 0.001)
                        }
                    }
                    let endpoint = try frame(anchor), endHeight = view.bounds.height
                    view.finishInteractiveTransition(commit: true, animated: false)
                    XCTAssertEqual(try frame(anchor).minY, endpoint.minY, accuracy: pixel)
                    XCTAssertEqual(try frame(anchor).height, endpoint.height, accuracy: pixel)
                    XCTAssertEqual(view.bounds.height, endHeight, accuracy: pixel)
                    XCTAssertEqual(try cell(anchor).titleLabel.stringValue, target.isContinuous ? (anchor.month == 3 ? "Mar" : "Jan") : "1")
                    XCTAssertNil(view.transition); XCTAssertNil(view.calendarLayout.focusedContinuousRow)
                    XCTAssertEqual(view.calendarLayout.continuousMonthOpacity, 1)
                    XCTAssertEqual(view.selectedDays, [previous, anchor])
                    XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
                }
                try view.focus(anchor)
                XCTAssertEqual(view.focusedDay, anchor)
                XCTAssertEqual(try cell(anchor).view.layer?.borderWidth, 0)
            }
        }
    }

    @MainActor func testContinuousResizeRestoresFractionalViewportAndCleansUp() throws {
        let view = try make(), spy = TransitionSpy()
        try view.setDisplayMode(.continuousMonths, animated: false)
        view.frame.size.height = 420; view.needsLayout = true; view.layoutSubtreeIfNeeded()
        var offset = view.scrollView.contentView.bounds.origin; offset.y += 13.25
        view.scrollView.contentView.scroll(to: offset)
        let original = view.scrollView.contentView.bounds.origin
        spy.heightChanged = { [weak view] in view?.frame.size.height = $0 }; view.delegate = spy
        view.prepareTransition(to: .week); view.updateInteractiveTransition(progress: 0.5)
        view.frame.size.width += 70.25; view.needsLayout = true; view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.transition); XCTAssertEqual(view.displayMode, .continuousMonths)
        XCTAssertEqual(view.bounds.height, 420)
        XCTAssertEqual(view.scrollView.contentView.bounds.minY, original.y, accuracy: 1)
        XCTAssertTrue(view.titleLabel.isHidden)
        XCTAssertTrue(view.collectionView.visibleItems().allSatisfy { $0.view.alphaValue == 1 })
        XCTAssertNil(view.calendarLayout.focusedContinuousRow)
    }

    @MainActor func testContinuousAnimatedReversalAndReduceMotionCleanup() async throws {
        let view = try make(), spy = TransitionSpy()
        try view.setDisplayMode(.continuousMonths, animated: false)
        view.frame.size.height = 420; view.needsLayout = true; view.layoutSubtreeIfNeeded()
        view.delegate = spy; view.reduceMotionOverride = false
        spy.heightChanged = { [weak view] in view?.frame.size.height = $0 }
        try view.setDisplayMode(.week)
        let original = try XCTUnwrap(view.transition)
        try view.setDisplayMode(.week)
        XCTAssertTrue(view.transition === original)
        let halfway = expectation(description: "timeline reaches intermediate geometry")
        spy.heightChanged = { [weak view] height in
            view?.frame.size.height = height
            if let progress = view?.transition?.progress, progress > 0.25 {
                spy.heightChanged = { [weak view] in view?.frame.size.height = $0 }
                halfway.fulfill()
            }
        }
        await fulfillment(of: [halfway], timeout: 3)
        let height = view.bounds.height
        try view.setDisplayMode(.continuousMonths)
        XCTAssertTrue(view.transition === original)
        XCTAssertEqual(view.bounds.height, height)
        XCTAssertFalse(original.settlingCommit)
        try view.setDisplayMode(.week); try view.setDisplayMode(.continuousMonths)
        XCTAssertTrue(view.transition === original); XCTAssertFalse(original.settlingCommit)
        let returned = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated { view.transitionState == .idle } }, evaluatedWith: nil)
        await fulfillment(of: [returned], timeout: 3)
        XCTAssertEqual(view.displayMode, .continuousMonths); XCTAssertEqual(view.bounds.height, 420)
        XCTAssertTrue(spy.modes.isEmpty)
        let finished = expectation(description: "real collapse completes")
        spy.completion = { finished.fulfill() }
        try view.setDisplayMode(.week)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(view.displayMode, .week)
        let expanded = expectation(description: "real expansion completes")
        spy.completion = { expanded.fulfill() }
        try view.setDisplayMode(.continuousMonths)
        await fulfillment(of: [expanded], timeout: 3)
        spy.completion = nil
        XCTAssertEqual(view.displayMode, .continuousMonths); XCTAssertEqual(view.bounds.height, 420)
        try view.setDisplayMode(.week)
        try view.setDisplayMode(.continuousMonths)
        view.reduceMotionOverride = true; view.accessibilityDisplayChanged()
        XCTAssertNil(view.transition); XCTAssertEqual(view.displayMode, .continuousMonths)
        XCTAssertEqual(view.bounds.height, 420)
        XCTAssertNil(view.calendarLayout.focusedContinuousRow)
        try view.setDisplayMode(.week)
        XCTAssertNil(view.transition); XCTAssertEqual(view.displayMode, .week)
    }

}
#endif
