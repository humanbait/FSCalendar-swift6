#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit

@MainActor private final class MonthLabelProvider: FSCalendarDataSource {
    var content = DayContent()
    func calendar(_ calendar: FSCalendarView, contentFor day: CivilDay) -> DayContent { content }
}

final class CalendarLayoutTests: XCTestCase {
    @MainActor func testMonthSeparatorGeometryMirroringAndDecorationLifecycle() throws {
        _ = NSApplication.shared
        for weekday in 1...7 {
            let engine = try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: weekday,
                minimumDate: CivilDay(year: 2023, month: 12, day: 15),
                maximumDate: CivilDay(year: 2024, month: 3, day: 20)))
            for width: CGFloat in [350.3, 490.7] {
                let layout = CalendarCollectionLayout()
                layout.mode = .continuousMonths; layout.rowHeight = 45.4121
                layout.continuousSections = engine.continuousMonthSections()
                layout.rows = layout.continuousSections.map(\.rowCount)
                let collection = NSCollectionView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
                collection.collectionViewLayout = layout; layout.viewport = collection.frame.size
                let scale = max(1, collection.window?.backingScaleFactor ?? 1)
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
                        let visible = layout.layoutAttributesForElements(in: global)
                        XCTAssertTrue(visible.contains { $0.representedElementKind == kind && $0.indexPath?.section == section })
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
                    layout.monthSeparatorColor = .separatorColor
                }
                let all = layout.layoutAttributesForElements(in: CGRect(origin: .zero, size: layout.collectionViewContentSize))
                XCTAssertEqual(all.filter { $0.representedElementKind == kind }.count, 3)
                let decoration = MonthSeparatorView(frame: .zero)
                decoration.apply(try separator(1))
                XCTAssertNil(decoration.hitTest(.zero))
                XCTAssertFalse(decoration.isAccessibilityElement())
                layout.mode = .week
                XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 1)))
            }
        }
    }
    @MainActor func testContinuousMonthLabelsLocaleCustomTitlesAndReuse() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 400))
        let provider = MonthLabelProvider(); view.dataSource = provider
        try view.setDisplayMode(.continuousMonths, animated: false)
        let cell = FSCalendarItem()
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
                XCTAssertEqual(cell.titleLabel.stringValue, formatter.shortStandaloneMonthSymbols[month - 1])
                let accessibility = cell.view.accessibilityLabel()
                if locale == "en_US_POSIX" {
                    XCTAssertEqual(cell.titleLabel.stringValue, month == 1 ? "Jan" : "Mar")
                    XCTAssertTrue(accessibility?.contains(month == 1 ? "January 1, 2024" : "March 1, 2024") == true)
                }
                for customTitle in ["Launch", ""] {
                    provider.content = DayContent(title: customTitle, subtitle: "Note", image: NSImage(systemSymbolName: "heart", accessibilityDescription: nil))
                    view.configure(cell, occurrence: occurrences[0])
                    XCTAssertEqual(cell.titleLabel.stringValue, customTitle)
                    XCTAssertEqual(cell.subtitleLabel.stringValue, "Note")
                    XCTAssertNotNil(cell.dayImageView.image)
                    XCTAssertEqual(cell.view.accessibilityLabel(), accessibility)
                }
                provider.content = DayContent(accessibilityLabel: "Custom date")
                view.configure(cell, occurrence: occurrences[0])
                XCTAssertEqual(cell.view.accessibilityLabel(), "Custom date")
                cell.prepareForReuse(); provider.content = DayContent()
                view.configure(cell, occurrence: occurrences[1])
                XCTAssertEqual(cell.titleLabel.stringValue, "2")
                XCTAssertNil(cell.dayImageView.image)
                try view.setDisplayMode(.week, animated: false)
                view.configure(cell, occurrence: occurrences[0])
                XCTAssertEqual(cell.titleLabel.stringValue, "1")
                try view.setDisplayMode(.continuousMonths, animated: false)
            }
        }
    }

    @MainActor func testContinuousBoundarySelectionReloadHeadingAndScopeRoundTrip() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 350, height: 400))
        let provider = MonthLabelProvider(); view.dataSource = provider
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        let leapDay = try CivilDay(year: 2024, month: 2, day: 29)
        let march = try CivilDay(year: 2024, month: 3, day: 1)
        for placeholders: PlaceholderMode in [.none, .variable, .sixRows] {
            try view.apply(configuration: CalendarConfiguration(placeholders: placeholders,
                minimumDate: CivilDay(year: 2024, month: 2, day: 10),
                maximumDate: CivilDay(year: 2024, month: 3, day: 20),
                timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"), selectionMode: .multiple))
            try view.setDisplayMode(.continuousMonths, animated: false)
            try view.setCurrentPage(march, animated: false)
            view.layoutSubtreeIfNeeded(); view.collectionView.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.currentPage, march)
            XCTAssertTrue(view.titleLabel.isHidden)
            XCTAssertEqual(view.calendarLayout.itemCount(in: 0), 29)
            XCTAssertEqual(view.calendarLayout.itemCount(in: 1), 31)
            XCTAssertFalse(try XCTUnwrap(view.controller.grid(0)).occurrences[8].isSelectable)
            let headingFrame = view.titleLabel.frame
            XCTAssertEqual(headingFrame.height, 0)
            XCTAssertEqual(view.weekdayLabels[0].frame.minY, 0)
            let cells = view.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }
            let days = cells.compactMap { $0.dayState?.occurrence.day }
            XCTAssertEqual(Set(days).count, days.count)
            XCTAssertTrue(cells.allSatisfy { $0.dayState?.occurrence.position == .current })
            let last = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == leapDay })
            let first = try XCTUnwrap(cells.first { $0.dayState?.occurrence.day == march })
            XCTAssertEqual(last.view.frame.minY, first.view.frame.minY, accuracy: 0.01)
            XCTAssertEqual(last.view.frame.maxX, first.view.frame.minX, accuracy: 0.01)
            try view.setSelection([leapDay, march])
            XCTAssertEqual(last.dayState?.isSelected, true)
            XCTAssertEqual(first.dayState?.isSelected, true)
            view.today = leapDay; view.reload(dates: [leapDay, march])
            XCTAssertEqual(last.dayState?.isToday, true)
            XCTAssertEqual(first.titleLabel.stringValue, "Mar")
            provider.content = DayContent(title: "Launch")
            view.reload(dates: [march])
            XCTAssertEqual(first.titleLabel.stringValue, "Launch")
            provider.content = DayContent(); view.reload(dates: [march])
            XCTAssertEqual(first.titleLabel.stringValue, "Mar")
            XCTAssertTrue(first.view.accessibilityLabel()?.contains("March 1, 2024") == true)
            let originalOffset = view.scrollView.contentView.bounds.origin
            try view.focus(leapDay); view.input.moveFocus(1)
            XCTAssertEqual(view.focusedDay, march)
            XCTAssertEqual(view.scrollView.contentView.bounds.origin, originalOffset)

            var point = view.calendarLayout.offset(for: 1)
            point.y -= view.calendarLayout.rowHeight
            view.scrollView.contentView.scroll(to: point); view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
            XCTAssertEqual(view.currentPage, leapDay.startOfMonth)
            XCTAssertTrue(view.titleLabel.isHidden)
            point = view.calendarLayout.offset(for: 1)
            view.scrollView.contentView.scroll(to: point); view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
            XCTAssertEqual(view.currentPage, march)
            XCTAssertEqual(view.titleLabel.frame, headingFrame)
            try view.setDisplayMode(.week, animated: false)
            view.layoutSubtreeIfNeeded()
            XCTAssertFalse(view.titleLabel.isHidden)
            XCTAssertGreaterThan(view.titleLabel.frame.height, 0)
            try view.setDisplayMode(.continuousMonths, animated: false)
            view.layoutSubtreeIfNeeded(); view.collectionView.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.selectedDays, [leapDay, march])
            XCTAssertEqual(view.currentPage, march)
            XCTAssertLessThanOrEqual(view.cachedPageCount, 9)
        }
    }
    @MainActor func testContinuousSharedWeeksGeometryAndNavigation() throws {
        _ = NSApplication.shared
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
                let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 350, height: 400))
                collection.collectionViewLayout = layout
                layout.viewport = collection.frame.size
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
                        let attributes = layout.layoutAttributesForElements(in: rect).filter { $0.representedElementCategory == .item }
                        XCTAssertEqual(attributes.count, 7)
                        XCTAssertEqual(Set(attributes.compactMap { $0.indexPath?.section }), [section - 1, section])
                    }
                }
                let last = layout.continuousSections.count - 1
                XCTAssertGreaterThanOrEqual(layout.collectionViewContentSize.height, layout.offset(for: last).y + 400)
            }
        }
    }
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
    @MainActor func testContinuousHeadingRemovalRTLAndPagedScrollSettling() throws {
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
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(view.titleLabel.isHidden)
        XCTAssertEqual(view.titleLabel.frame.height, 0)
        XCTAssertTrue(view.titleLabel.isHidden)
        XCTAssertTrue(view.collectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).isEmpty)
        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }
}
#endif
