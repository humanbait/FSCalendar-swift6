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
                func decoration(_ kind: String, _ section: Int) throws -> MonthSeparatorAttributes {
                    try XCTUnwrap(layout.layoutAttributesForDecorationView(ofKind: kind,
                        at: IndexPath(item: 0, section: section)) as? MonthSeparatorAttributes)
                }
                XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 0)))
                XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 4)))
                for section in 1..<layout.continuousSections.count {
                    layout.isRTL = false
                    let a = try decoration(kind, section)
                    let path = try XCTUnwrap(a.path)
                    let column = layout.continuousSections[section].startSlot % 7
                    var curves = 0
                    path.applyWithBlock { if $0.pointee.type == .addCurveToPoint { curves += 1 } }
                    XCTAssertEqual(curves, column == 0 ? 0 : 2)
                    XCTAssertGreaterThan(a.zIndex, 0)
                    XCTAssertEqual(a.lineWidth, 1 / scale)
                    let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)))
                    XCTAssertEqual(a.frame.minY, first.frame.minY, accuracy: 0.5 / scale)
                    XCTAssertEqual(path.boundingBoxOfPath.width, a.frame.width, accuracy: 0.00001)
                    XCTAssertEqual(path.boundingBoxOfPath.minY, 0.5 / scale, accuracy: 0.00001)
                    let visible = layout.layoutAttributesForElements(in: a.frame)
                    XCTAssertTrue(visible.contains { $0.representedElementKind == kind && $0.indexPath?.section == section })
                    let copy = try XCTUnwrap(a.copy() as? MonthSeparatorAttributes)
                    XCTAssertTrue(a.isEqual(copy))
                    copy.lineWidth *= 2
                    XCTAssertFalse(a.isEqual(copy))
                    copy.lineWidth = a.lineWidth; copy.color = .red
                    XCTAssertFalse(a.isEqual(copy))
                    copy.color = a.color; copy.path = nil
                    XCTAssertFalse(a.isEqual(copy))
                    layout.isRTL = true
                    let mirrored = try decoration(kind, section)
                    var mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: a.frame.width, ty: 0)
                    XCTAssertEqual(path.copy(using: &mirror), mirrored.path)
                    layout.monthSeparatorCornerRadius = 0
                    let square = try XCTUnwrap(decoration(kind, section).path)
                    var squareCurves = 0
                    square.applyWithBlock { if $0.pointee.type == .addCurveToPoint { squareCurves += 1 } }
                    XCTAssertEqual(squareCurves, 0)
                    layout.monthSeparatorCornerRadius = 8
                    layout.monthSeparatorColor = .red
                    XCTAssertEqual(try decoration(kind, section).color, .red)
                    layout.monthSeparatorColor = .separatorColor
                }
                let all = layout.layoutAttributesForElements(in: CGRect(origin: .zero, size: layout.collectionViewContentSize))
                XCTAssertEqual(all.filter { $0.representedElementKind == kind }.count, 3)
                XCTAssertEqual(all.filter { $0.representedElementKind == MonthSeparatorView.backgroundKind }.count, 4)
                let view = MonthSeparatorView(frame: .zero)
                for kind in [kind, MonthSeparatorView.backgroundKind] {
                    view.apply(try decoration(kind, 1))
                    XCTAssertNil(view.hitTest(.zero))
                    XCTAssertFalse(view.isAccessibilityElement())
                }
                for mode: CalendarDisplayMode in [.week, .month(.horizontal), .month(.vertical)] {
                    layout.mode = mode
                    for kind in [kind, MonthSeparatorView.backgroundKind] {
                        XCTAssertNil(layout.layoutAttributesForDecorationView(ofKind: kind, at: IndexPath(item: 0, section: 1)))
                    }
                }
            }
        }
    }

    @MainActor func testMonthBackgroundOwnershipParityAndCustomization() throws {
        _ = NSApplication.shared
        for weekday in 1...7 {
            let engine = try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: weekday,
                minimumDate: CivilDay(year: 2023, month: 12, day: 15),
                maximumDate: CivilDay(year: 2024, month: 3, day: 20)))
            let layout = CalendarCollectionLayout()
            layout.mode = .continuousMonths; layout.rowHeight = 45.4121
            layout.continuousSections = engine.continuousMonthSections()
            layout.rows = layout.continuousSections.map(\.rowCount)
            layout.monthBackgroundColor = .white; layout.alternatingMonthBackgroundColor = .gray
            let width: CGFloat = 350.3
            let collection = NSCollectionView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
                collection.collectionViewLayout = layout; layout.viewport = collection.frame.size
            defer { withExtendedLifetime(collection) {} }
            func backgrounds() throws -> [MonthSeparatorAttributes] {
                try layout.continuousSections.indices.map { section in
                    try XCTUnwrap(layout.layoutAttributesForDecorationView(ofKind: MonthSeparatorView.backgroundKind,
                        at: IndexPath(item: 0, section: section)) as? MonthSeparatorAttributes)
                }
            }
            func contains(_ attribute: MonthSeparatorAttributes, _ point: CGPoint) -> Bool {
                attribute.path?.contains(CGPoint(x: point.x - attribute.frame.minX, y: point.y - attribute.frame.minY)) == true
            }
            for rtl in [false, true] {
                layout.isRTL = rtl
                let fills = try backgrounds()
                for (section, fill) in fills.enumerated() {
                    XCTAssertLessThan(fill.zIndex, 0)
                    XCTAssertEqual(fill.lineWidth, 0)
                    XCTAssertEqual(fill.color, section % 2 == 0 ? .gray : .white) // December is even.
                    for item in 0..<layout.continuousSections[section].dayCount {
                        let cell = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: item, section: section)))
                        let center = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
                        XCTAssertTrue(contains(fill, center))
                        XCTAssertEqual(fills.filter { contains($0, center) }.count, 1)
                    }
                }
                // Shared rows are completely tiled, including the space around both rounded bends.
                for section in layout.continuousSections.dropFirst() {
                    let y = CGFloat(section.firstRow) * layout.rowHeight
                    for dx in stride(from: CGFloat(0.137), to: width - 1, by: 3.7) {
                        for dy in stride(from: CGFloat(0.137), to: layout.rowHeight, by: 2.3) {
                            XCTAssertEqual(fills.filter { contains($0, CGPoint(x: dx, y: y + dy)) }.count, 1)
                        }
                    }
                }
                let first = layout.continuousSections[0]
                let last = try XCTUnwrap(layout.continuousSections.last)
                let end = last.startSlot + last.dayCount
                for slot in Array(0..<first.startSlot) + Array(end..<(end / 7 + 1) * 7) {
                    let column = rtl ? 6 - slot % 7 : slot % 7
                    let center = CGPoint(x: (CGFloat(column) + 0.5) * width / 7,
                                         y: (CGFloat(slot / 7) + 0.5) * layout.rowHeight)
                    XCTAssertFalse(fills.contains { contains($0, center) })
                }
            }
            // Shifting the configured start month must not recolor January, February or March.
            let shifted = try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: weekday,
                minimumDate: CivilDay(year: 2024, month: 1, day: 1),
                maximumDate: CivilDay(year: 2024, month: 3, day: 20)))
            layout.continuousSections = shifted.continuousMonthSections()
            XCTAssertEqual(try backgrounds().map(\.color), [.white, .gray, .white])
            layout.alternatingMonthBackgroundColor = .red
            XCTAssertEqual(try backgrounds()[1].color, .red)
            layout.alternatingMonthBackgroundColor = nil
            XCTAssertTrue(try backgrounds().allSatisfy { $0.color == .white })
            layout.monthBackgroundColor = .blue
            XCTAssertTrue(try backgrounds().allSatisfy { $0.color == .blue })
        }
    }

    @MainActor func testMonthCornerClampingAndPixelAlignment() throws {
        for scale: CGFloat in [1, 2, 3] {
            for column in 0...6 {
                let boundary = MonthBoundaryGeometry(slot: 7 + column, width: 70, rowHeight: 9.375,
                    scale: scale, cornerRadius: 1000)
                XCTAssertGreaterThanOrEqual(boundary.radius, 0)
                XCTAssertLessThanOrEqual(boundary.radius, 5)
                let geometry = MonthDecorationGeometry(boundary: boundary, width: 70, scale: scale, isRTL: false)
                XCTAssertEqual(geometry.frame.minY * scale, (geometry.frame.minY * scale).rounded(), accuracy: 0.00001)
                XCTAssertEqual(geometry.frame.maxY * scale, (geometry.frame.maxY * scale).rounded(), accuracy: 0.00001)
                XCTAssertTrue(geometry.path.boundingBoxOfPath.width.isFinite)
            }
        }
        var appearance = FSCalendarAppearance()
        for (input, expected): (CGFloat, CGFloat) in [(-1, 0), (.nan, 8), (.infinity, 8), (0, 0), (8, 8)] {
            appearance.monthSeparatorCornerRadius = input
            XCTAssertEqual(appearance.resolved().monthSeparatorCornerRadius, expected)
        }
        let alternate = try XCTUnwrap(appearance.alternatingMonthBackgroundColor)
        var values: [NSColor] = []
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                let resolved = alternate.usingColorSpace(.deviceRGB)!
                values.append(resolved)
                XCTAssertNotEqual(resolved, appearance.backgroundColor.usingColorSpace(.deviceRGB))
            }
        }
        XCTAssertNotEqual(values[0], values[1])
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
