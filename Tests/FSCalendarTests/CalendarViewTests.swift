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
    var pages: [CivilDay] = []
    func calendarCurrentPageDidChange(_ calendar: FSCalendar) { pages.append(calendar.currentPage) }
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

@MainActor private final class MonthLabelProvider: FSCalendarDataSource {
    var content = DayContent()
    func calendar(_ calendar: FSCalendar, contentFor day: CivilDay) -> DayContent { content }
}

final class CalendarViewTests: XCTestCase {
    @MainActor func testMonthSeparatorGeometryMirroringAndDecorationLifecycle() throws {
        for weekday in 1...7 {
            let engine = try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: weekday,
                minimumDate: CivilDay(year: 2023, month: 12, day: 15),
                maximumDate: CivilDay(year: 2024, month: 3, day: 20)))
            for width: CGFloat in [350.3, 490.7] {
                let layout = CalendarCollectionLayout()
                layout.mode = .continuousMonths; layout.rowHeight = 45.4121
                layout.continuousSections = engine.continuousMonthSections()
                layout.rows = layout.continuousSections.map(\.rowCount)
                let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: width, height: 400), collectionViewLayout: layout)
                let scale = max(1, collection.traitCollection.displayScale)
                let kind = MonthSeparatorView.kind
                func separator(_ section: Int) throws -> MonthSeparatorAttributes {
                    try XCTUnwrap(layout.layoutAttributesForDecorationView(ofKind: kind,
                        at: IndexPath(item: 0, section: section)) as? MonthSeparatorAttributes)
                }
                XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 0)))
                XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 4)))
                for section in 1..<layout.continuousSections.count {
                    layout.isRTL = false
                    let a = try separator(section)
                    let column = layout.continuousSections[section].startSlot % 7
                    XCTAssertEqual(a.segments.count, column == 0 ? 1 : 3)
                    XCTAssertGreaterThan(a.zIndex, 0)
                    let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)))
                    XCTAssertEqual(a.frame.minY, first.frame.minY, accuracy: 0.5 / scale)
                    XCTAssertEqual(a.segments.last?.maxX, a.frame.width)
                    XCTAssertEqual(a.segments.last?.minY, 0)
                    if column != 0 {
                        XCTAssertEqual(a.segments[1].minX, first.frame.minX, accuracy: 0.5 / scale)
                        XCTAssertEqual(a.frame.minY + a.segments[0].minY, first.frame.maxY, accuracy: 0.5 / scale)
                    }
                    for segment in a.segments {
                        XCTAssertEqual(min(segment.width, segment.height), 1 / scale, accuracy: 0.00001)
                        let global = segment.offsetBy(dx: a.frame.minX, dy: a.frame.minY)
                        for value in [global.minX, global.minY, global.width, global.height] {
                            XCTAssertEqual(value * scale, (value * scale).rounded(), accuracy: 0.00001)
                        }
                        let visible = (layout.layoutAttributesForElements(in: global) ?? [])
                        XCTAssertTrue(visible.contains { $0.representedElementKind == kind && $0.indexPath.section == section })
                    }
                    let copy = try XCTUnwrap(a.copy() as? MonthSeparatorAttributes)
                    XCTAssertTrue(a.isEqual(copy))
                    copy.color = .red
                    XCTAssertFalse(a.isEqual(copy))
                    layout.isRTL = true
                    let mirrored = try separator(section)
                    for (left, right) in zip(a.segments, mirrored.segments) {
                        XCTAssertEqual(left.minX, a.frame.width - right.maxX, accuracy: 0.00001)
                        XCTAssertEqual(left.minY, right.minY)
                    }
                    layout.monthSeparatorColor = .red
                    XCTAssertEqual(try separator(section).color, .red)
                    layout.monthSeparatorColor = .separator
                }
                let all = (layout.layoutAttributesForElements(in: CGRect(origin: .zero, size: layout.collectionViewContentSize)) ?? [])
                XCTAssertEqual(all.filter { $0.representedElementKind == kind }.count, 3)
                let decoration = MonthSeparatorView(frame: .zero)
                decoration.apply(try separator(1))
                XCTAssertFalse(decoration.isUserInteractionEnabled)
                XCTAssertFalse(decoration.isAccessibilityElement)
                layout.mode = .week
                XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 1)))
            }
        }
    }
    @MainActor func testContinuousMonthLabelsLocaleCustomTitlesAndReuse() throws {

        let view = FSCalendar(frame: CGRect(x: 0, y: 0, width: 350, height: 400))
        let provider = MonthLabelProvider(); view.dataSource = provider
        try view.setDisplayMode(.continuousMonths, animated: false)
        let cell = FSCalendarCell(frame: .zero)
        for locale in ["en_US_POSIX", "de_DE", "ru_RU", "zh_CN"] {
            try view.apply(configuration: CalendarConfiguration(
                minimumDate: CivilDay(year: 2023, month: 12, day: 1),
                maximumDate: CivilDay(year: 2024, month: 3, day: 31),
                timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: locale)))
            let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = view.configuration.locale
            for month in [1, 3] {
                let day = try CivilDay(year: 2024, month: month, day: 1)
                let occurrences = try view.engine.continuousMonthGrid(containing: day).occurrences
                provider.content = DayContent()
                view.configure(cell, occurrence: occurrences[0])
                XCTAssertEqual(cell.titleLabel.text, formatter.shortStandaloneMonthSymbols[month - 1])
                let accessibility = cell.accessibilityLabel
                if locale == "en_US_POSIX" {
                    XCTAssertEqual(cell.titleLabel.text, month == 1 ? "Jan" : "Mar")
                    XCTAssertTrue(accessibility?.contains(month == 1 ? "January 1, 2024" : "March 1, 2024") == true)
                }
                for customTitle in ["Launch", ""] {
                    provider.content = DayContent(title: customTitle, subtitle: "Note", image: UIImage(systemName: "heart"))
                    view.configure(cell, occurrence: occurrences[0])
                    XCTAssertEqual(cell.titleLabel.text, customTitle)
                    XCTAssertEqual(cell.subtitleLabel.text, "Note")
                    XCTAssertNotNil(cell.dayImageView.image)
                    XCTAssertEqual(cell.accessibilityLabel, accessibility)
                }
                provider.content = DayContent(accessibilityLabel: "Custom date")
                view.configure(cell, occurrence: occurrences[0])
                XCTAssertEqual(cell.accessibilityLabel, "Custom date")
                cell.prepareForReuse(); provider.content = DayContent()
                view.configure(cell, occurrence: occurrences[1])
                XCTAssertEqual(cell.titleLabel.text, "2")
                XCTAssertNil(cell.dayImageView.image)
                try view.setDisplayMode(.week, animated: false)
                view.configure(cell, occurrence: occurrences[0])
                XCTAssertEqual(cell.titleLabel.text, "1")
                try view.setDisplayMode(.continuousMonths, animated: false)
            }
        }
    }

    @MainActor private func hostForAnimation(_ calendar: FSCalendar, height initialHeight: CGFloat? = nil) -> (UIWindow, CalendarSpy) {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(calendar)
        calendar.translatesAutoresizingMaskIntoConstraints = false
        let height = calendar.heightAnchor.constraint(equalToConstant: initialHeight ?? calendar.preferredHeight)
        NSLayoutConstraint.activate([height, calendar.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 100),
            calendar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            calendar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)])
        let spy = CalendarSpy()
        spy.onHeight = { [weak calendar, weak controller] in
            guard let calendar else { return }
            height.constant = calendar.transitionState == .idle && calendar.displayMode.isContinuous
                ? (initialHeight ?? calendar.preferredHeight) : calendar.preferredHeight
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

    @MainActor private func waitForAnimationFrame(_ description: String, _ condition: @escaping @MainActor () -> Bool) {
        let matched = expectation(description: description)
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
            let isMatched = MainActor.assumeIsolated { condition() }
            if isMatched { timer.invalidate(); matched.fulfill() }
        }
        defer { timer.invalidate() }
        wait(for: [matched], timeout: 3)
    }

    @MainActor func testContinuousBoundarySelectionReloadHeadingAndScopeRoundTrip() throws {
        let view = FSCalendar(frame: CGRect(x: 0, y: 0, width: 350, height: 400))
        let provider = MonthLabelProvider(); view.dataSource = provider
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.addSubview(view); window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let leapDay = try CivilDay(year: 2024, month: 2, day: 29)
        let march = try CivilDay(year: 2024, month: 3, day: 1)
        for placeholders: PlaceholderMode in [.none, .variable, .sixRows] {
            try view.apply(configuration: CalendarConfiguration(placeholders: placeholders,
                minimumDate: CivilDay(year: 2024, month: 2, day: 10),
                maximumDate: CivilDay(year: 2024, month: 3, day: 20),
                timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"), selectionMode: .multiple))
            try view.setDisplayMode(.continuousMonths, animated: false)
            try view.setCurrentPage(march, animated: false)
            view.layoutIfNeeded(); view.collectionView.layoutIfNeeded()
            XCTAssertEqual(view.currentPage, march)
            XCTAssertTrue(view.titleLabel.isHidden)
            XCTAssertEqual(view.calendarLayout.itemCount(in: 0), 29)
            XCTAssertEqual(view.calendarLayout.itemCount(in: 1), 31)
            XCTAssertFalse(try XCTUnwrap(view.grid(in: 0)).occurrences[8].isSelectable)
            let headingFrame = view.titleLabel.frame
            XCTAssertEqual(headingFrame.height, 0)
            XCTAssertEqual(view.weekdayStack.frame.minY, 0)
            let cells = view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }
            let days = cells.compactMap { $0.dayState?.occurrence.day }
            XCTAssertEqual(Set(days).count, days.count)
            XCTAssertTrue(cells.allSatisfy { $0.dayState?.occurrence.position == .current })
            let last = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == leapDay })
            let first = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == march })
            XCTAssertEqual(last.frame.minY, first.frame.minY, accuracy: 0.01)
            XCTAssertEqual(last.frame.maxX, first.frame.minX, accuracy: 0.01)
            try view.setSelection([leapDay, march])
            XCTAssertEqual(last.dayState?.isSelected, true)
            XCTAssertEqual(first.dayState?.isSelected, true)
            view.today = leapDay; view.reload(dates: [leapDay, march])
            XCTAssertEqual(last.dayState?.isToday, true)
            XCTAssertEqual(first.titleLabel.text, "Mar")
            provider.content = DayContent(title: "Launch")
            view.reload(dates: [march])
            XCTAssertEqual(first.titleLabel.text, "Launch")
            provider.content = DayContent(); view.reload(dates: [march])
            XCTAssertEqual(first.titleLabel.text, "Mar")
            XCTAssertTrue(first.accessibilityLabel?.contains("March 1, 2024") == true)

            var point = view.calendarLayout.offset(for: 1)
            point.y -= view.calendarLayout.rowHeight
            view.collectionView.setContentOffset(point, animated: false)
            XCTAssertEqual(view.currentPage, leapDay.startOfMonth)
            XCTAssertTrue(view.titleLabel.isHidden)
            point = view.calendarLayout.offset(for: 1)
            view.collectionView.setContentOffset(point, animated: false)
            XCTAssertEqual(view.currentPage, march)
            XCTAssertEqual(view.titleLabel.frame, headingFrame)
            try view.setDisplayMode(.week, animated: false)
            view.layoutIfNeeded()
            XCTAssertFalse(view.titleLabel.isHidden)
            XCTAssertGreaterThan(view.titleLabel.frame.height, 0)
            try view.setDisplayMode(.continuousMonths, animated: false)
            view.layoutIfNeeded(); view.collectionView.layoutIfNeeded()
            XCTAssertEqual(view.selectedDays, [leapDay, march])
            XCTAssertEqual(view.currentPage, march)
            XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
        }
    }
    @MainActor func testContinuousSharedWeeksGeometryAndNavigation() throws {

        let minimum = try CivilDay(year: 2023, month: 12, day: 15)
        let maximum = try CivilDay(year: 2024, month: 3, day: 20)
        for weekday in 1...7 {
            let engine = try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: weekday,
                minimumDate: minimum, maximumDate: maximum))
            for rtl in [false, true] {
                let layout = CalendarCollectionLayout()
                layout.mode = .continuousMonths; layout.rowHeight = 45.4121; layout.isRTL = rtl
                layout.continuousSections = engine.continuousMonthSections()
                layout.rows = layout.continuousSections.map(\.rowCount)
                let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 350, height: 400), collectionViewLayout: layout)
                _ = collection
                layout.prepare()
                var frames: [CGRect] = []
                for (section, month) in layout.continuousSections.enumerated() {
                    XCTAssertEqual(layout.itemCount(in: section), month.dayCount)
                    let offset = layout.offset(for: section)
                    XCTAssertEqual(layout.section(at: offset), section)
                    if section > 0 {
                        XCTAssertEqual(layout.section(at: CGPoint(x: 0, y: offset.y - 1)), section - 1)
                    }
                    for item in 0..<month.dayCount {
                        let index = IndexPath(item: item, section: section)
                        let frame = try XCTUnwrap(layout.layoutAttributesForItem(at: index)).frame
                        let day = try month.page.anchor.addingDays(item)
                        let column = (day.weekday - weekday + 7) % 7
                        XCTAssertEqual(frame.minX, CGFloat(rtl ? 6 - column : column) * 50, accuracy: 0.0001)
                        if let previous = frames.last {
                            let sameRow = column != 0
                            XCTAssertEqual(frame.minY, previous.minY + (sameRow ? 0 : layout.rowHeight), accuracy: 0.0001)
                            if sameRow {
                                XCTAssertEqual(rtl ? frame.maxX : previous.maxX, rtl ? previous.minX : frame.minX, accuracy: 0.0001)
                            }
                        }
                        frames.append(frame)
                    }
                    if section > 0, month.startSlot % 7 != 0 {
                        let rect = CGRect(x: 0, y: offset.y + 1, width: 350, height: layout.rowHeight - 2)
                        let attributes = (layout.layoutAttributesForElements(in: rect) ?? []).filter { $0.representedElementCategory == .cell }
                        XCTAssertEqual(attributes.count, 7)
                        XCTAssertEqual(Set(attributes.map(\.indexPath.section)), [section - 1, section])
                    }
                }
                let last = layout.continuousSections.count - 1
                XCTAssertGreaterThanOrEqual(layout.collectionViewContentSize.height, layout.offset(for: last).y + 400)
            }
        }
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
        view.reduceMotionOverride = false
        let pixel = 1 / max(1, view.traitCollection.displayScale)
        waitForAnimationFrame("Initial month frame is presented") {
            abs((view.layer.presentation()?.bounds.height ?? 0) - monthHeight) <= pixel
        }
        try view.beginInteractiveTransition(to: .week)
        view.updateInteractiveTransition(progress: 0.6)
        let dragHeight = view.preferredHeight
        waitForAnimationFrame("Interactive height is presented before cancellation") {
            abs((view.layer.presentation()?.bounds.height ?? 0) - dragHeight) <= pixel
        }
        view.finishInteractiveTransition(commit: false, animated: true)
        XCTAssertEqual(view.transition?.animator?.duration, 0.3)
        waitForAnimationFrame("Cancellation animates through intermediate height") {
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

    @MainActor func testContinuousScopeKeepsBoundaryWeekAndViewportInOneAnimation() throws {
        let view = try make(.multiple)
        try view.setDisplayMode(.continuousMonths, animated: false)
        let (window, spy) = hostForAnimation(view, height: 400)
        defer { window.isHidden = true }
        view.reduceMotionOverride = false
        let boundary = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
        try view.setSelection(boundary)
        try view.setCurrentPage(boundary[0], animated: false)
        view.layoutIfNeeded()
        view.collectionView.contentOffset.y += 13.25
        let initialOffset = view.collectionView.contentOffset
        let pixel = 1 / view.traitCollection.displayScale
        func cell(_ day: CivilDay) throws -> FSCalendarCell {
            try XCTUnwrap(view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }.first {
                $0.dayState?.occurrence.day == day
            })
        }
        let originalY = try cell(boundary[1]).convert(cell(boundary[1]).bounds, to: view).minY
        try view.prepareTransition(to: .week)
        let context = try XCTUnwrap(view.transition)
        XCTAssertTrue(context.isContinuousScope)
        XCTAssertEqual(context.sourceHeight, 400, accuracy: pixel)
        XCTAssertEqual(view.collectionView.contentOffset, initialOffset)
        XCTAssertEqual(try cell(boundary[1]).convert(cell(boundary[1]).bounds, to: view).minY, originalY, accuracy: pixel)
        for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            view.updateInteractiveTransition(progress: progress)
            XCTAssertEqual(view.bounds.height, 400 + (context.targetHeight - 400) * progress, accuracy: pixel)
            for day in boundary {
                XCTAssertEqual(try cell(day).alpha, 1)
                XCTAssertEqual(try cell(day).convert(cell(day).bounds, to: view).minY,
                    originalY + (view.effectiveHeaderHeight + view.effectiveWeekdayHeight - originalY) * progress, accuracy: pixel)
            }
        }
        let beforeCommit = try cell(boundary[1]).convert(cell(boundary[1]).bounds, to: view)
        view.finishInteractiveTransition(commit: true, animated: false)
        XCTAssertEqual(try cell(boundary[1]).convert(cell(boundary[1]).bounds, to: view).minY, beforeCommit.minY, accuracy: pixel)
        XCTAssertEqual(try cell(boundary[1]).titleLabel.text, "1")
        let weekHeight = view.bounds.height
        try view.setDisplayMode(.continuousMonths)
        XCTAssertEqual(view.transition?.targetHeight, 400)
        XCTAssertEqual(view.transition?.animator?.duration, 0.3)
        waitForAnimationFrame("Continuous viewport expands through an intermediate height") {
            guard let height = view.layer.presentation()?.bounds.height else { return false }
            return height > weekHeight + 1 && height < 399
        }
        waitUntil("Continuous scope finishes") { view.transitionState == .idle }
        XCTAssertEqual(view.bounds.height, 400, accuracy: pixel)
        XCTAssertEqual(try cell(boundary[1]).titleLabel.text, "Mar")
        XCTAssertTrue(view.titleLabel.isHidden)
        XCTAssertEqual(view.selectedDays, boundary)
        XCTAssertEqual(spy.heights.last, 400)
    }

    @MainActor func testContinuousScopeReversesAndIgnoresRepeatedTarget() throws {
        let view = try make()
        try view.setDisplayMode(.continuousMonths, animated: false)
        let (window, spy) = hostForAnimation(view, height: 400)
        defer { withExtendedLifetime(spy) {}; window.isHidden = true }
        view.reduceMotionOverride = false
        waitForAnimationFrame("Continuous viewport is presented") {
            abs((view.layer.presentation()?.bounds.height ?? 0) - 400) < 0.5
        }
        try view.setDisplayMode(.week)
        let context = try XCTUnwrap(view.transition)
        try view.setDisplayMode(.week)
        XCTAssertTrue(view.transition === context)
        waitForAnimationFrame("Collapse is underway") {
            let height = view.layer.presentation()?.bounds.height ?? 400
            return height < 399 && height > context.targetHeight + 1
        }
        try view.setDisplayMode(.continuousMonths)
        XCTAssertTrue(view.transition === context)
        XCTAssertTrue(try XCTUnwrap(context.animator).isReversed)
        waitUntil("Reversal returns to the continuous viewport") { view.transitionState == .idle }
        XCTAssertEqual(view.displayMode, .continuousMonths)
        XCTAssertEqual(view.bounds.height, 400, accuracy: 0.5)
        XCTAssertEqual(view.collectionView.transform, .identity)
        XCTAssertTrue(view.collectionView.isScrollEnabled)
        XCTAssertTrue(context.titleFades.allSatisfy { $0.outgoing.superview == nil && $0.label.alpha == 1 })
    }

    @MainActor func testContinuousScopeFractionalGeometryRTLAndResizeCancellation() throws {
        for rtl in [false, true] {
            let view = try make(.multiple)
            view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            view.appearance.rowHeight = 61.375
            try view.setDisplayMode(.continuousMonths, animated: false)
            let (window, spy) = hostForAnimation(view, height: 400.5)
            defer { withExtendedLifetime(spy) {}; window.isHidden = true }
            let days = try [CivilDay(year: 2024, month: 2, day: 29), CivilDay(year: 2024, month: 3, day: 1)]
            try view.setSelection(days)
            try view.setCurrentPage(days[1], animated: false)
            view.layoutIfNeeded()
            let offset = view.collectionView.contentOffset
            try view.prepareTransition(to: .week)
            let context = try XCTUnwrap(view.transition)
            view.updateInteractiveTransition(progress: 0.5)
            let cells = view.collectionView.visibleCells.compactMap { $0 as? FSCalendarCell }
            let first = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == days[0] })
            let second = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == days[1] })
            XCTAssertEqual(first.alpha, 1); XCTAssertEqual(second.alpha, 1)
            XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 0.01)
            XCTAssertEqual(first.frame.height, view.effectiveRowHeight, accuracy: 0.01)
            XCTAssertEqual(first.frame.minX > second.frame.minX, rtl)
            window.frame.size.width -= 30.5
            window.rootViewController?.view.frame.size.width -= 30.5
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            XCTAssertEqual(view.transitionState, .idle)
            XCTAssertEqual(view.displayMode, .continuousMonths)
            XCTAssertEqual(view.collectionView.contentOffset.y, offset.y, accuracy: 0.5)
            XCTAssertEqual(view.bounds.height, 400.5, accuracy: 0.5)
            XCTAssertTrue(context.titleFades.allSatisfy { $0.outgoing.superview == nil })
            XCTAssertEqual(view.selectedDays, days)
        }
    }

    @MainActor func testVariableMonthHeightAnimatesAndRapidReversalEndsAtLatestPage() throws {
        let view = try make()
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        let shortHeight = view.preferredHeight
        view.reduceMotionOverride = false
        let pixel = 1 / max(1, view.traitCollection.displayScale)
        waitForAnimationFrame("Initial month frame is presented") {
            abs((view.layer.presentation()?.bounds.height ?? 0) - shortHeight) <= pixel
        }
        try view.setCurrentPage(CivilDay(year: 2024, month: 3, day: 1), animated: true)
        let tallHeight = view.preferredHeight
        waitForAnimationFrame("Month height animates between endpoints") {
            guard let height = view.layer.presentation()?.bounds.height else { return false }
            return height > shortHeight + 0.1 && height < tallHeight - 0.1
        }
        try view.setCurrentPage(CivilDay(year: 2024, month: 2, day: 1), animated: true)
        waitUntil("Reversal reaches the latest height") {
            guard let height = view.layer.presentation()?.bounds.height else { return false }
            return abs(height - shortHeight) <= pixel
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

    @MainActor func testSwipeReleaseStartsHeightChangeBeforeScrollingEnds() throws {
        for rtl in [false, true] {
            let view = try make()
            view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
            try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
            let (window, spy) = hostForAnimation(view)
            defer { window.isHidden = true }
            for month in [3, 2] {
                let sourceHeight = view.preferredHeight
                let sourceOffset = view.collectionView.contentOffset
                let target = try CivilDay(year: 2024, month: month, day: 1)
                let section = try view.engine.sectionIndex(for: target, scope: .month)
                var offset = view.calendarLayout.offset(for: section)
                let releaseOffset = CGPoint(x: sourceOffset.x + (offset.x - sourceOffset.x) * 0.6, y: 0)
                view.collectionView.setContentOffset(releaseOffset, animated: false)
                spy.pages.removeAll(); spy.heights.removeAll()
                view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &offset)
                let targetHeight = view.preferredHeight
                XCTAssertNotEqual(sourceHeight, targetHeight)
                XCTAssertEqual(view.currentPage, target)
                XCTAssertEqual(spy.pages, [target])
                XCTAssertEqual(spy.heights, [targetHeight])
                XCTAssertEqual(view.collectionView.contentOffset.x, releaseOffset.x, accuracy: 0.5)
                // Model the remaining UIScrollView deceleration and observe both presentations together.
                view.collectionView.setContentOffset(offset, animated: true)
                waitForAnimationFrame("Page and height animate concurrently") {
                    guard let height = view.layer.presentation()?.bounds.height,
                          let x = view.collectionView.layer.presentation()?.bounds.origin.x else { return false }
                    return height > min(sourceHeight, targetHeight) + 0.1 && height < max(sourceHeight, targetHeight) - 0.1 &&
                        x > min(releaseOffset.x, offset.x) + 0.1 && x < max(releaseOffset.x, offset.x) - 0.1
                }
                waitUntil("Page finishes scrolling") { abs(view.collectionView.contentOffset.x - offset.x) < 0.1 }
                view.scrollViewDidEndDecelerating(view.collectionView)
                XCTAssertEqual(spy.pages, [target])
                XCTAssertEqual(spy.heights, [targetHeight])
            }
        }
    }

    @MainActor func testSwipeReversalAndNondeceleratingReleaseReconcileWithoutDuplicateCallbacks() throws {
        let view = try make()
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        let february = view.currentPage, sourceOffset = view.collectionView.contentOffset
        var samePage = sourceOffset
        view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &samePage)
        view.scrollViewDidEndDragging(view.collectionView, willDecelerate: false)
        XCTAssertTrue(spy.pages.isEmpty); XCTAssertTrue(spy.heights.isEmpty)
        let march = try CivilDay(year: 2024, month: 3, day: 1)
        var target = view.calendarLayout.offset(for: try view.engine.sectionIndex(for: march, scope: .month))
        view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &target)
        var reverse = sourceOffset
        view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &reverse)
        view.scrollViewDidEndDragging(view.collectionView, willDecelerate: false)
        view.scrollViewDidEndDecelerating(view.collectionView)
        XCTAssertEqual(spy.pages, [march, february])
        XCTAssertEqual(spy.heights.count, 2)
        XCTAssertEqual(view.currentPage, february)
    }

    @MainActor func testVerticalSwipeRemapsDestinationAndPreservesFractionalPosition() throws {
        let view = try make()
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        try view.setDisplayMode(.month(.vertical), animated: false)
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        for month in [3, 2] {
            let section = try view.engine.sectionIndex(for: CivilDay(year: 2024, month: month, day: 1), scope: .month)
            let previousExtent = view.collectionView.bounds.height
            let fraction = CGFloat(section) + (month == 3 ? -0.4 : 0.4)
            view.collectionView.setContentOffset(CGPoint(x: 0, y: fraction * previousExtent), animated: false)
            var target = view.calendarLayout.offset(for: section)
            view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &target)
            XCTAssertNotEqual(view.collectionView.bounds.height, previousExtent)
            XCTAssertEqual(view.collectionView.contentOffset.y / view.collectionView.bounds.height, fraction, accuracy: 0.001)
            XCTAssertEqual(target.y, view.calendarLayout.offset(for: section).y, accuracy: 0.001)
            let count = spy.pages.count
            view.collectionView.setContentOffset(target, animated: false)
            view.scrollViewDidEndDecelerating(view.collectionView)
            XCTAssertEqual(spy.pages.count, count)
            XCTAssertEqual(view.currentPage.month, month)
        }
    }

    @MainActor func testFixedRowSwipeOnlyNotifiesPageAndReduceMotionIsImmediate() throws {
        let view = try make()
        view.reduceMotionOverride = true
        let (window, spy) = hostForAnimation(view)
        defer { window.isHidden = true }
        view.notifyHeight(animated: false); spy.heights.removeAll()
        let march = try CivilDay(year: 2024, month: 3, day: 1)
        var target = view.calendarLayout.offset(for: try view.engine.sectionIndex(for: march, scope: .month))
        view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &target)
        XCTAssertEqual(spy.pages, [march]); XCTAssertTrue(spy.heights.isEmpty)
        try view.apply(configuration: CalendarConfiguration(placeholders: .variable, timeZone: TimeZone(secondsFromGMT: 0)!))
        var february = view.calendarLayout.offset(for: try view.engine.sectionIndex(for: CivilDay(year: 2024, month: 2, day: 1), scope: .month))
        view.scrollViewWillEndDragging(view.collectionView, withVelocity: .zero, targetContentOffset: &february)
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
        for mode: CalendarDisplayMode in [.month(.horizontal), .continuousMonths] {
            try view.setDisplayMode(mode, animated: false)
            for year in 2020...2029 {
                for month in 1...12 {
                    try view.setCurrentPage(CivilDay(year: year, month: month, day: 1), animated: false)
                    view.layoutIfNeeded()
                }
            }
            XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
            XCTAssertGreaterThan(view.cachedPageCount, 0)
        }
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
    @MainActor func testRTLGeometry() throws {
        let layout = CalendarCollectionLayout()
        layout.rows = [4, 6]; layout.rowHeight = 44
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 350, height: 300), collectionViewLayout: layout)
        _ = collection
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
    @MainActor func testCompactWeekdayBandAlignsWithGridAcrossDisplayModes() throws {
        let view = try make()
        XCTAssertEqual(view.appearance.weekdayHeight, 18)
        for mode: CalendarDisplayMode in [.month(.horizontal), .week, .continuousMonths] {
            try view.setDisplayMode(mode, animated: false)
            view.frame.size.height = view.preferredHeight
            view.layoutIfNeeded()
            XCTAssertEqual(view.weekdayStack.frame.height,
                           max(18, view.resolvedAppearance.weekdayFont.lineHeight + 4), accuracy: 0.001)
            XCTAssertEqual(view.clipView.frame.minY, view.weekdayStack.frame.maxY, accuracy: 0.001)
        }
    }
    @MainActor func testWeekdayHeightFallbackAndCustomHeight() throws {
        let view = try make()
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            var appearance = view.appearance
            appearance.weekdayHeight = invalid
            view.appearance = appearance
            XCTAssertEqual(view.resolvedAppearance.weekdayHeight, 18)
        }
        var appearance = view.appearance
        appearance.weekdayHeight = 40
        view.appearance = appearance
        view.layoutIfNeeded()
        XCTAssertEqual(view.weekdayStack.frame.height, max(40, view.resolvedAppearance.weekdayFont.lineHeight + 4), accuracy: 0.001)
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
        XCTAssertGreaterThan(view.effectiveWeekdayHeight, 18)
        XCTAssertGreaterThanOrEqual(view.weekdayStack.frame.height, view.resolvedAppearance.weekdayFont.lineHeight + 4)
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
