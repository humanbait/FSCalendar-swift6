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
    var heights: [CGFloat] = []
    var onHeight: (() -> Void)?
    func calendar(_ calendar: FSCalendar, preferredHeightDidChange height: CGFloat, animated: Bool) {
        heights.append(height)
        onHeight?()
    }
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
    @MainActor private func hostForAnimation(_ calendar: FSCalendar) -> (UIWindow, CalendarSpy) {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(calendar)
        calendar.translatesAutoresizingMaskIntoConstraints = false
        let height = calendar.heightAnchor.constraint(equalToConstant: calendar.preferredHeight)
        NSLayoutConstraint.activate([height, calendar.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 100),
            calendar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            calendar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)])
        let spy = CalendarSpy()
        spy.onHeight = { [weak calendar, weak controller] in
            guard let calendar else { return }
            height.constant = calendar.preferredHeight
            controller?.view.layoutIfNeeded()
        }
        calendar.delegate = spy
        window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        return (window, spy)
    }

    @MainActor private func waitUntil(_ description: String, _ condition: @escaping @MainActor () -> Bool) {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        expectation.expectationDescription = description
        wait(for: [expectation], timeout: 3)
    }

    @MainActor func testSelectionBounceOnlyForAcceptedAdditionsAndClearsOnReuse() throws {
        let view = try make(.multiple)
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        let cell = try XCTUnwrap(view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.first { $0.dayState?.occurrence.day == day })
        try view.select(day)
        let bounce = try XCTUnwrap(cell.selectionBackground.layer.animation(forKey: "selectionBounce") as? CAKeyframeAnimation)
        XCTAssertEqual(bounce.duration, 0.15)
        XCTAssertEqual(bounce.values as? [Double], [0.3, 1.2, 1])
        XCTAssertEqual(bounce.keyTimes, [0, 0.75, 1])
        cell.selectionBackground.layer.removeAnimation(forKey: "selectionBounce")
        view.reload(dates: [day]); try view.select(day)
        XCTAssertNil(cell.selectionBackground.layer.animation(forKey: "selectionBounce"))
        try view.deselect(day)
        spy.allow = false
        XCTAssertThrowsError(try view.select(day))
        XCTAssertNil(cell.selectionBackground.layer.animation(forKey: "selectionBounce"))
        spy.allow = true
        try view.transact([day], origin: .user)
        XCTAssertNotNil(cell.selectionBackground.layer.animation(forKey: "selectionBounce"))
        try view.deselect(day)
        XCTAssertNil(cell.selectionBackground.layer.animation(forKey: "selectionBounce"))
        try view.select(day)
        cell.prepareForReuse()
        XCTAssertNil(cell.selectionBackground.layer.animation(forKey: "selectionBounce"))
        XCTAssertEqual(cell.alpha, 1)
    }

    @MainActor func testScopeDragCoordinatesHeightOffsetAndOpacityInBothDirections() throws {
        let view = try make()
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        try view.select(CivilDay(year: 2024, month: 2, day: 14))
        for target in [CalendarDisplayMode.week, .month(.horizontal)] {
            try view.beginInteractiveTransition(to: target)
            let context = try XCTUnwrap(view.transition)
            for progress: CGFloat in [0, 0.25, 0.75, 1] {
                view.updateInteractiveTransition(progress: progress)
                XCTAssertEqual(view.bounds.height, context.sourceHeight + (context.targetHeight - context.sourceHeight) * progress, accuracy: 0.5)
                let ratio = target == .week ? progress : 1 - progress
                XCTAssertEqual(view.collectionView.transform.ty, -context.rowOffset * ratio, accuracy: 0.01)
                for cell in view.collectionView.visibleCells {
                    let index = try XCTUnwrap(view.collectionView.indexPath(for: cell))
                    let expected: CGFloat = index.item / 7 == context.focusedRow ? 1 : (target == .week ? max(1 - 1.1 * progress, 0) : progress)
                    XCTAssertEqual(cell.alpha, expected, accuracy: 0.01)
                }
            }
            view.finishInteractiveTransition(commit: true, animated: false)
            XCTAssertTrue(view.collectionView.visibleCells.allSatisfy { $0.alpha == 1 })
            XCTAssertEqual(view.collectionView.transform, .identity)
        }
        XCTAssertFalse(spy.heights.isEmpty)
    }

    @MainActor func testAnimatedScopeCommitAndCancellationPreserveIntermediateGeometry() throws {
        let view = try make()
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        let monthHeight = view.preferredHeight
        try view.beginInteractiveTransition(to: .week)
        view.updateInteractiveTransition(progress: 0.6)
        let dragHeight = view.preferredHeight
        view.finishInteractiveTransition(commit: false, animated: true)
        XCTAssertEqual(view.transition?.animator?.duration, 0.3)
        waitUntil("Cancellation animates through intermediate height") {
            guard let height = view.layer.presentation()?.bounds.height else { return false }
            return height > dragHeight + 0.1 && height < monthHeight - 0.1
        }
        waitUntil("Cancellation finishes") { view.transitionState == .idle }
        XCTAssertEqual(view.bounds.height, monthHeight, accuracy: 0.5)
        XCTAssertEqual(view.displayMode, .month(.horizontal))
        try view.setDisplayMode(.week, animated: true)
        waitUntil("Scope commit finishes") { view.transitionState == .idle }
        XCTAssertEqual(view.displayMode, .week)
        XCTAssertEqual(view.bounds.height, view.preferredHeight, accuracy: 0.5)
        XCTAssertFalse(spy.heights.isEmpty)
    }

    @MainActor func testVariableMonthHeightAnimatesAndRapidReversalEndsAtLatestPage() throws {
        let view = try make()
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        let shortHeight = view.preferredHeight
        try view.setCurrentPage(CivilDay(year: 2024, month: 3, day: 1), animated: true)
        let tallHeight = view.preferredHeight
        waitUntil("Month height animates between endpoints") {
            guard let height = view.layer.presentation()?.bounds.height else { return false }
            return height > shortHeight + 0.1 && height < tallHeight - 0.1
        }
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 1), animated: true)
        waitUntil("Reversal reaches the latest height") {
            guard let height = view.layer.presentation()?.bounds.height else { return false }
            return abs(height - shortHeight) < 0.1
        }
        XCTAssertEqual(view.currentPage, try CivilDay(year: 2024, month: 2, day: 1))
        XCTAssertEqual(view.bounds.height, shortHeight, accuracy: 0.5)
        XCTAssertEqual(spy.heights.last, shortHeight)
    }

    @MainActor func testReduceMotionSkipsSelectionScopeAndMonthHeightAnimations() throws {
        let view = try make()
        view.reduceMotionOverride = true
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        try view.select(day)
        let cell = try XCTUnwrap(view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.first { $0.dayState?.occurrence.day == day })
        XCTAssertNil(cell.selectionBackground.layer.animation(forKey: "selectionBounce"))
        try view.setCurrentPage(CivilDay(year: 2024, month: 3, day: 1), animated: true)
        XCTAssertEqual(view.bounds.height, view.preferredHeight, accuracy: 0.5)
        XCTAssertNil(view.layer.animation(forKey: "bounds.size"))
        try view.setDisplayMode(.week, animated: true)
        XCTAssertEqual(view.transitionState, .idle)
        XCTAssertEqual(view.displayMode, .week)
        XCTAssertEqual(view.bounds.height, view.preferredHeight, accuracy: 0.5)
        XCTAssertFalse(spy.heights.isEmpty)
    }

    @MainActor func testNonanimatedAndSameHeightPageChangesDoNotAnimateHeight() throws {
        let view = try make()
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        view.notifyHeight(animated: false)
        let height = view.preferredHeight
        try view.setCurrentPage(CivilDay(year: 2024, month: 3, day: 1), animated: true)
        XCTAssertEqual(spy.heights, [height])
        XCTAssertNil(view.layer.animation(forKey: "bounds.size"))
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 1), animated: false)
        XCTAssertEqual(view.bounds.height, view.preferredHeight, accuracy: 0.5)
        XCTAssertNil(view.layer.animation(forKey: "bounds.size"))
    }

    @MainActor func testHeightNotificationsTrackDelegateIdentityAndPreventReentrantDuplicates() throws {
        let view = try make()
        let first = CalendarSpy(), second = CalendarSpy()
        view.delegate = first
        first.onHeight = { [weak view] in view?.notifyHeight(animated: false) }
        view.notifyHeight(animated: false)
        view.notifyHeight(animated: true)
        view.delegate = first
        view.notifyHeight(animated: false)
        XCTAssertEqual(first.heights, [view.preferredHeight])
        view.delegate = second
        view.notifyHeight(animated: false)
        XCTAssertEqual(second.heights, [view.preferredHeight])
        view.delegate = nil
        view.notifyHeight(animated: false)
        view.delegate = second
        view.notifyHeight(animated: false)
        XCTAssertEqual(second.heights.count, 2)
    }

    @MainActor func testHeightNotificationsPreserveScopeAndInteractiveCancellation() throws {
        let view = try make(), spy = CalendarSpy()
        view.delegate = spy
        view.notifyHeight(animated: false)
        let monthHeight = view.preferredHeight
        try view.setDisplayMode(.week, animated: false)
        let weekHeight = view.preferredHeight
        XCTAssertLessThan(weekHeight, monthHeight)
        try view.setDisplayMode(.month(.horizontal), animated: false)
        XCTAssertEqual(spy.heights, [monthHeight, weekHeight, monthHeight])
        try view.beginInteractiveTransition(to: .week)
        view.updateInteractiveTransition(progress: 0.5)
        let middleHeight = view.preferredHeight
        view.updateInteractiveTransition(progress: 0.5)
        view.finishInteractiveTransition(commit: false, animated: false)
        XCTAssertEqual(spy.heights, [monthHeight, weekHeight, monthHeight, middleHeight, monthHeight])
        XCTAssertEqual(view.intrinsicContentSize.height, monthHeight)
    }

    @MainActor func testVariableRowNavigationDeliversChangedHeight() throws {
        let view = try make(), spy = CalendarSpy()
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        view.delegate = spy
        view.notifyHeight(animated: false)
        let februaryHeight = view.preferredHeight
        try view.setCurrentPage(CivilDay(year: 2024, month: 3, day: 1), animated: false)
        let marchHeight = view.preferredHeight
        XCTAssertGreaterThan(marchHeight, februaryHeight)
        XCTAssertEqual(spy.heights, [februaryHeight, marchHeight])
    }

    @MainActor func testLegacyCellContentAlignment() throws {
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        let engine = try CalendarEngine(configuration: CalendarConfiguration())
        let occurrence = try XCTUnwrap(engine.grid(containing: day, scope: .month).occurrences.first { $0.day == day })
        let cell = FSCalendarCell(frame: .zero)
        for (size, expectedDiameter) in [(CGSize(width: 116, height: 44), CGFloat(35)), (CGSize(width: 70, height: 60), CGFloat(125) / 3), (CGSize(width: 28, height: 32), CGFloat(80) / 3)] {
            cell.frame = CGRect(origin: .zero, size: size)
            for events in [0, 3] {
                for subtitle in [nil, "Lunar"] as [String?] {
                    for hasImage in [false, true] {
                        for stateFlags in [(false, false), (true, false), (false, true)] {
                            cell.apply(content: DayContent(subtitle: subtitle, image: hasImage ? UIImage(systemName: "heart.fill") : nil, numberOfEvents: events),
                                       state: DayState(occurrence: occurrence, isSelected: stateFlags.0, isToday: stateFlags.1),
                                       appearance: FSCalendarAppearance(), style: DayAppearance(cornerRadius: 7))
                            cell.setNeedsLayout(); cell.layoutIfNeeded()
                            let textFrame = subtitle == nil ? cell.titleLabel.frame : cell.titleLabel.frame.union(cell.subtitleLabel.frame)
                            XCTAssertEqual(cell.selectionBackground.frame.width, expectedDiameter, accuracy: 0.5)
                            XCTAssertEqual(textFrame.midY, cell.selectionBackground.frame.midY, accuracy: 0.5)
                            XCTAssertEqual(cell.selectionBackground.frame.midY, size.height * 5 / 12, accuracy: 0.5)
                            if !hasImage { XCTAssertEqual(cell.titleLabel.frame.midX, size.width / 2, accuracy: 0.5) }
                            XCTAssertEqual(cell.selectionBackground.layer.cornerRadius, 7)
                            let stack = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? UIStackView }.first)
                            XCTAssertEqual(stack.isHidden, events == 0)
                            if events > 0 { XCTAssertGreaterThan(stack.frame.minY, cell.selectionBackground.frame.maxY) }
                        }
                    }
                }
            }
        }
        cell.prepareForReuse()
        cell.apply(content: DayContent(), state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                   appearance: FSCalendarAppearance(), style: DayAppearance())
        cell.setNeedsLayout(); cell.layoutIfNeeded()
        XCTAssertNil(cell.dayImageView.image)
        XCTAssertEqual(cell.titleLabel.frame.midY, cell.selectionBackground.frame.midY, accuracy: 0.5)
        XCTAssertEqual(cell.selectionBackground.frame.width, 80 / 3, accuracy: 0.5)
    }

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
        let spy = CalendarSpy(); view.delegate = spy
        view.notifyHeight(animated: false)
        let before = view.preferredHeight
        let fontSize = view.resolvedAppearance.titleFont.pointSize
        parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: child)
        parent.view.layoutIfNeeded(); child.view.layoutIfNeeded(); view.layoutIfNeeded()
        XCTAssertEqual(view.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(view.resolvedAppearance.titleFont.pointSize, fontSize)
        XCTAssertGreaterThan(view.preferredHeight, before)
        XCTAssertEqual(spy.heights.last, view.preferredHeight)
        XCTAssertGreaterThan(spy.heights.count, 1)
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
