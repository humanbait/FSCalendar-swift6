#if canImport(UIKit)
import UIKit
import XCTest
#if SWIFT_PACKAGE
import CalendarContractSupport
#endif
import FSCalendarCore
@testable import FSCalendar

@MainActor private final class CalendarSpy: FSCalendarDelegate {
    var changes: [SelectionChange] = []
    var allow = true
    var reentrantError: CalendarError?
    var attemptReentry = false
    func calendar(_ calendar: FSCalendar, shouldApply change: SelectionChange) -> Bool {
        if attemptReentry {
            do { try calendar.clearSelection() } catch { reentrantError = error as? CalendarError }
        }
        return allow
    }
    func calendar(_ calendar: FSCalendar, didChangeSelection change: SelectionChange) { changes.append(change) }
}

extension FSCalendar: RendererSelectionContract {}

final class CalendarViewTests: XCTestCase {
    @MainActor func testSharedSelectionContract() throws {
        let view = try make(); let spy = CalendarSpy(); view.delegate = spy
        try SharedRendererAssertions.verifySelection(view, changes: { spy.changes }, allow: { spy.allow = $0 })
    }
    @MainActor private func make(_ mode: SelectionMode = .single) throws -> FSCalendar {
        let view = FSCalendar(frame: CGRect(x: 0, y: 0, width: 390, height: 340))
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!, selectionMode: mode))
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14), animated: false)
        view.layoutIfNeeded()
        return view
    }
    @MainActor func testProgrammaticSelectionEmitsOneAtomicChangeAndNoOpEmitsNone() throws {
        let view = try make()
        let spy = CalendarSpy(); view.delegate = spy
        let a = try CivilDay(year: 2024, month: 2, day: 12), b = try CivilDay(year: 2024, month: 2, day: 14)
        try view.select(a); try view.select(a); try view.select(b)
        XCTAssertEqual(spy.changes.count, 2)
        XCTAssertEqual(spy.changes.last?.added, [b])
        XCTAssertEqual(spy.changes.last?.removed, [a])
        XCTAssertEqual(view.selectedDays, [b])
    }
    @MainActor func testVetoAndInvalidRequestLeaveStateUnchanged() throws {
        let view = try make(); let spy = CalendarSpy(); view.delegate = spy; spy.allow = false
        XCTAssertThrowsError(try view.select(CivilDay(year: 2024, month: 2, day: 14)))
        XCTAssertTrue(view.selectedDays.isEmpty)
        XCTAssertTrue(spy.changes.isEmpty)
        XCTAssertThrowsError(try view.select(CivilDay(year: 1900, month: 1, day: 1)))
    }
    @MainActor func testDelegateReentryIsRejected() throws {
        let view = try make(); let spy = CalendarSpy(); view.delegate = spy; spy.attemptReentry = true
        try view.select(CivilDay(year: 2024, month: 2, day: 14))
        XCTAssertEqual(spy.reentrantError, .reentrantMutation)
        XCTAssertEqual(spy.changes.count, 1)
    }
    @MainActor func testConfigurationPrunesSelectionEvenWhenDelegateVetoes() throws {
        let view = try make(.multiple)
        let a = try CivilDay(year: 2024, month: 2, day: 12), b = try CivilDay(year: 2024, month: 2, day: 14)
        try view.select(a); try view.select(b)
        let spy = CalendarSpy(); spy.allow = false; view.delegate = spy
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!))
        XCTAssertEqual(view.selectedDays, [b])
        XCTAssertEqual(spy.changes.count, 1)
        XCTAssertEqual(spy.changes.first?.origin, .configuration)
    }
    @MainActor func testInteractiveCancellationRestoresSourceModePageAndHeight() throws {
        let view = try make()
        let page = view.currentPage, height = view.preferredHeight
        try view.beginInteractiveTransition(to: .week)
        view.updateInteractiveTransition(progress: 0.7)
        XCTAssertEqual(view.displayMode, .month(.horizontal))
        view.finishInteractiveTransition(commit: false, animated: false)
        XCTAssertEqual(view.transitionState, .idle)
        XCTAssertEqual(view.displayMode, .month(.horizontal))
        XCTAssertEqual(view.currentPage, page)
        XCTAssertEqual(view.preferredHeight, height, accuracy: 0.1)
    }
    @MainActor func testTransitionCompletionAndReplacementUseLatestTarget() throws {
        let view = try make()
        try view.beginInteractiveTransition(to: .week)
        view.updateInteractiveTransition(progress: 0.5)
        try view.setDisplayMode(.month(.vertical), animated: false)
        XCTAssertEqual(view.displayMode, .month(.vertical))
        XCTAssertEqual(view.transitionState, .idle)
        try view.setDisplayMode(.week, animated: false)
        XCTAssertEqual(view.displayMode, .week)
    }
    @MainActor func testRepeatedNavigationKeepsDetailedCacheBounded() throws {
        let view = try make()
        for year in 2020...2029 {
            for month in 1...12 {
                try view.setCurrentPage(CivilDay(year: year, month: month, day: 1), animated: false)
                view.layoutIfNeeded()
            }
        }
        XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
        XCTAssertGreaterThan(view.cachedPageCount, 0)
    }
    @MainActor func testWeekHeightAndIntrinsicSizing() throws {
        let view = try make()
        let monthHeight = view.intrinsicContentSize.height
        try view.setDisplayMode(.week, animated: false)
        XCTAssertLessThan(view.intrinsicContentSize.height, monthHeight)
        XCTAssertEqual(view.intrinsicContentSize.height, view.preferredHeight)
    }
    @MainActor func testResizeCancelsAnInteractiveTransition() throws {
        let view = try make()
        let page = view.currentPage
        try view.beginInteractiveTransition(to: .week)
        view.updateInteractiveTransition(progress: 0.4)
        view.frame.size.width += 80
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertEqual(view.transitionState, .idle)
        XCTAssertEqual(view.displayMode, .month(.horizontal))
        XCTAssertEqual(view.currentPage, page)
    }
    @MainActor func testMultipleSelectionSynchronizesCollectionViewSelection() throws {
        let view = try make(.multiple)
        let a = try CivilDay(year: 2024, month: 2, day: 12), b = try CivilDay(year: 2024, month: 2, day: 14)
        try view.select(a); try view.select(b)
        view.layoutIfNeeded()
        let selected = view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.filter { $0.isSelected }
        XCTAssertEqual(Set(selected.compactMap { $0.dayState?.occurrence.day }), [a, b])
        try view.deselect(a)
        XCTAssertFalse(view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.contains { $0.dayState?.occurrence.day == a && $0.isSelected })
    }
    @MainActor func testStickyHeadersAndRTLGeometry() throws {
        let layout = CalendarCollectionLayout()
        layout.rows = [4, 6]; layout.rowHeight = 44; layout.headerHeight = 40
        layout.mode = .continuousMonths
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 350, height: 300), collectionViewLayout: layout)
        layout.prepare()
        collection.contentOffset.y = 80
        let header = try XCTUnwrap(layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(header.frame.minY, 80)
        XCTAssertEqual(header.zIndex, 100)
        collection.contentOffset.y = 200
        XCTAssertEqual(layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0))?.frame.minY, 176)
        layout.mode = .month(.horizontal); layout.isRTL = true; layout.prepare()
        let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(first.frame.minX, 650)
        XCTAssertEqual(layout.section(at: CGPoint(x: 350, y: 0)), 0)
        let view = try make()
        view.semanticContentAttribute = .forceRightToLeft
        view.setNeedsLayout(); view.layoutIfNeeded()
        let weekdays = view.weekdayStack.arrangedSubviews.compactMap { ($0 as? UILabel)?.accessibilityLabel }
        XCTAssertEqual(weekdays, ["Saturday", "Friday", "Thursday", "Wednesday", "Tuesday", "Monday", "Sunday"])
    }
    @MainActor func testContinuousNavigationKeepsTheRequestedMonthAtFractionalRowHeights() throws {
        let view = try make()
        view.frame.size.height = 400
        var appearance = view.appearance; appearance.rowHeight = 45.4121; view.appearance = appearance
        try view.setDisplayMode(.continuousMonths, animated: false)
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 14), animated: false)
        view.layoutIfNeeded()
        XCTAssertEqual(view.currentPage, try CivilDay(year: 2024, month: 2, day: 1))
    }
    @MainActor func testDynamicTypeIncreasesFontAndPreferredHeight() throws {
        let view = try make()
        let parent = UIViewController(), child = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = parent; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        parent.addChild(child); parent.view.addSubview(child.view); child.didMove(toParent: parent)
        child.view.addSubview(view)
        let before = view.preferredHeight
        let fontSize = view.resolvedAppearance.titleFont.pointSize
        parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: child)
        parent.view.layoutIfNeeded(); child.view.layoutIfNeeded(); view.layoutIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(view.resolvedAppearance.titleFont.pointSize, fontSize)
        XCTAssertGreaterThan(view.preferredHeight, before)
        XCTAssertEqual((view.weekdayStack.arrangedSubviews.first as? UILabel)?.accessibilityLabel, "Sunday")
    }
    @MainActor func testInvalidAppearanceDimensionsCannotProduceNonfiniteGeometry() throws {
        let view = try make()
        var appearance = view.appearance
        appearance.rowHeight = .nan; appearance.headerHeight = .infinity; appearance.weekdayHeight = -100
        view.appearance = appearance; view.layoutIfNeeded()
        XCTAssertTrue(view.preferredHeight.isFinite)
        XCTAssertGreaterThan(view.preferredHeight, 0)
        XCTAssertTrue(view.collectionView.contentSize.width.isFinite)
    }
    @MainActor func testSelectionAndTargetedReloadSynchronizePlaceholderOccurrences() throws {
        let view = try make(.multiple)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(view); window.makeKeyAndVisible(); view.layoutIfNeeded()
        defer { window.isHidden = true }
        let day = try CivilDay(year: 2024, month: 2, day: 29)
        try view.select(day)
        let original = try XCTUnwrap(view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.first { $0.dayState?.occurrence.day == day })
        let identifier = original.accessibilityIdentifier
        try view.setCurrentPage(CivilDay(year: 2024, month: 3, day: 1))
        view.layoutIfNeeded()
        let placeholder = try XCTUnwrap(view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.first { $0.dayState?.occurrence.day == day })
        XCTAssertEqual(placeholder.dayState?.occurrence.position, .previous)
        XCTAssertTrue(placeholder.isSelected)
        XCTAssertEqual(placeholder.dayState?.isSelected, true)
        XCTAssertNotEqual(placeholder.accessibilityIdentifier, identifier)
        try view.deselect(day)
        XCTAssertFalse(placeholder.isSelected)
    }
}
#endif
