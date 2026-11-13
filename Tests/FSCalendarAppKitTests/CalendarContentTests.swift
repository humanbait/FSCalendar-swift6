#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
import FSCalendarCore
@testable import FSCalendarAppKit

@MainActor private final class ContentProvider: FSCalendarDataSource {
    var custom = true
    var identifier = "custom"
    func calendar(_ calendar: FSCalendarView, reuseIdentifierFor day: CivilDay) -> String? { identifier }
    func calendar(_ calendar: FSCalendarView, contentFor day: CivilDay) -> DayContent {
        custom ? DayContent(title: "X", subtitle: "Lunar", image: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Heart"), numberOfEvents: 3, accessibilityValue: "three events") : DayContent()
    }
}
@MainActor private final class CustomItem: FSCalendarItem {}
@MainActor private final class YearContentProvider: FSCalendarDataSource {
    var content = DayContent()
    func calendar(_ calendar: FSCalendarView, contentFor day: CivilDay) -> DayContent { content }
}
final class CalendarContentTests: XCTestCase {
    @MainActor func testYearEventsStayInlineAndMirrorInRTL() throws {
        _ = NSApplication.shared
        let day = try CivilDay(year: 2027, month: 1, day: 1)
        let occurrence = try XCTUnwrap(CalendarEngine(configuration: CalendarConfiguration()).continuousMonthGrid(containing: day).occurrences.first)
        let cell = FSCalendarItem()
        for width: CGFloat in [35.5, 56, 110] {
            cell.view.frame = CGRect(x: 0, y: 0, width: width, height: 60)
            for rtl in [false, true] {
                cell.view.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                for events in [0, 1, 3] {
                    cell.continuousCenteringProgress = 1; cell.hasAutomaticYearSubtitle = true
                    cell.apply(content: DayContent(title: "Jan", subtitle: "2027", numberOfEvents: events),
                        state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                        appearance: FSCalendarAppearance(), style: DayAppearance())
                    cell.viewDidLayout()
                    if events > 0 {
                        let dots = cell.view.subviews.filter { $0 !== cell.selectionBackground && !($0 is NSTextField) && !($0 is NSImageView) && !$0.isHidden }
                        let dotFrame = dots.reduce(CGRect.null) { $0.union($1.frame) }
                        XCTAssertEqual(dotFrame.midY, cell.subtitleLabel.frame.midY, accuracy: 0.001)
                        XCTAssertEqual(rtl ? cell.subtitleLabel.frame.minX - dotFrame.maxX : dotFrame.minX - cell.subtitleLabel.frame.maxX, 3, accuracy: 0.001)
                        let group = cell.subtitleLabel.frame.union(dotFrame)
                        if cell.subtitleLabel.frame.width + 2 * (dotFrame.width + 3) <= width - 4 {
                            XCTAssertEqual(cell.subtitleLabel.frame.midX, width / 2, accuracy: 0.001)
                        }
                        XCTAssertGreaterThanOrEqual(group.minX, 0)
                        XCTAssertLessThanOrEqual(group.maxX, width)
                    } else {
                        XCTAssertEqual(cell.subtitleLabel.frame.midX, width / 2, accuracy: 0.001)
                    }
                    cell.prepareForReuse()
                }
            }
        }
    }

    @MainActor func testContinuousCenteringAndYearContentPrecedence() throws {
        _ = NSApplication.shared
        let calendar = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 400))
        try calendar.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!))
        calendar.referenceDate = { Date(timeIntervalSince1970: 1767225600) } // 2026
        calendar.today = try CivilDay(year: 2027, month: 1, day: 1)
        let provider = YearContentProvider(); calendar.dataSource = provider
        let item = FSCalendarItem()
        item.view.frame.size = NSSize(width: 70.3, height: 44.5)
        for mode: CalendarDisplayMode in [.continuousMonths, .week, .month(.horizontal)] {
            try calendar.setDisplayMode(mode, animated: false)
            for year in [2025, 2026, 2027] {
                for month in [1, 6, 12] {
                    for number in [1, 2] {
                        let day = try CivilDay(year: year, month: month, day: number)
                        let occurrence = try XCTUnwrap(calendar.engine.continuousMonthGrid(containing: day).occurrences.first { $0.day == day })
                        for custom in [DayContent(), DayContent(title: "Launch"), DayContent(title: ""), DayContent(subtitle: "Note"), DayContent(subtitle: "")] {
                            provider.content = custom
                            item.prepareForReuse()
                            calendar.configure(item, occurrence: occurrence); item.viewDidLayout()
                            let automatic = mode.isContinuous && number == 1 && year != 2026 && custom.title == nil && custom.subtitle == nil
                            XCTAssertEqual(item.subtitleLabel.stringValue, automatic ? String(year) : (custom.subtitle ?? ""))
                            XCTAssertEqual(item.hasAutomaticYearSubtitle, automatic)
                            let center = mode.isContinuous ? 44.5 / 2 : 44.5 * 5 / 12
                            let group = item.subtitleLabel.stringValue.isEmpty ? item.titleLabel.frame : item.titleLabel.frame.union(item.subtitleLabel.frame)
                            XCTAssertEqual(group.midY, center, accuracy: 0.001)
                            XCTAssertEqual(item.selectionBackground.frame.midY, center, accuracy: 0.001)
                            XCTAssertEqual(item.subtitleLabel.alphaValue, 1)
                        }
                    }
                }
            }
        }
    }

    @MainActor func testContinuousYearFontFittingEventsAndReuse() throws {
        _ = NSApplication.shared
        let day = try CivilDay(year: 2027, month: 1, day: 1)
        let occurrence = try XCTUnwrap(CalendarEngine(configuration: CalendarConfiguration()).continuousMonthGrid(containing: day).occurrences.first)
        let item = FSCalendarItem()
        var appearance = FSCalendarAppearance()
        appearance.titleFont = .systemFont(ofSize: 40)
        appearance.subtitleFont = .systemFont(ofSize: 30)
        for selected in [false, true] {
            for hasImage in [false, true] {
                item.continuousCenteringProgress = 1; item.hasAutomaticYearSubtitle = true
                item.apply(content: DayContent(title: "Jan", subtitle: "2027",
                    image: hasImage ? NSImage(systemSymbolName: "heart", accessibilityDescription: nil) : nil, numberOfEvents: 3),
                    state: DayState(occurrence: occurrence, isSelected: selected, isToday: true), appearance: appearance, style: DayAppearance())
                var largeFont: NSFont?
                for size in [NSSize(width: 110, height: 80), NSSize(width: 35.5, height: 44.5), NSSize(width: 110, height: 80)] {
                    item.view.frame.size = size; item.viewDidLayout()
                    XCTAssertEqual(item.titleLabel.frame.union(item.subtitleLabel.frame).midY, size.height / 2, accuracy: 0.001)
                    for label in [item.titleLabel, item.subtitleLabel] {
                        let font = try XCTUnwrap(label.font)
                        XCTAssertLessThanOrEqual((label.stringValue as NSString).size(withAttributes: [.font: font]).width, label.frame.width)
                    }
                    if size.width == 110 {
                        if let largeFont { XCTAssertEqual(item.titleLabel.font, largeFont) }
                        largeFont = item.titleLabel.font
                    }
                    XCTAssertEqual(item.subtitleLabel.textColor, selected ? appearance.selectedTitleColor : appearance.subtitleColor)
                    let dots = item.view.subviews.filter { $0 !== item.selectionBackground && !($0 is NSTextField) && !($0 is NSImageView) && !$0.isHidden }
                    XCTAssertEqual(dots.count, 3)
                    for dot in dots {
                        XCTAssertEqual(dot.frame.midY, item.subtitleLabel.frame.midY, accuracy: 0.001)
                        XCTAssertLessThanOrEqual(dot.frame.maxY, size.height)
                    }
                }
                item.prepareForReuse()
                XCTAssertFalse(item.hasAutomaticYearSubtitle)
                XCTAssertEqual(item.continuousCenteringProgress, 0)
                XCTAssertEqual(item.subtitleLabel.alphaValue, 1)
            }
        }
    }

    @MainActor func testYearRolloverActivationWakeAndTimeZoneRefresh() throws {
        _ = NSApplication.shared
        let calendar = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 400))
        try calendar.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!))
        var instant = Date(timeIntervalSince1970: 1798761599)
        calendar.referenceDate = { instant }
        try calendar.setDisplayMode(.continuousMonths, animated: false)
        let window = NSWindow(contentRect: calendar.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = calendar; window.orderFront(nil)
        defer { window.close() }
        let january = try CivilDay(year: 2027, month: 1, day: 1)
        try calendar.setCurrentPage(january); calendar.layoutSubtreeIfNeeded()
        func item() throws -> FSCalendarItem {
            try XCTUnwrap(calendar.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }.first { $0.dayState?.occurrence.day == january })
        }
        XCTAssertEqual(try item().subtitleLabel.stringValue, "2027")
        let offset = calendar.scrollView.contentView.bounds.origin
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, NSApplication.didBecomeActiveNotification] {
            instant = Date(timeIntervalSince1970: 1798761601)
            NotificationCenter.default.post(name: name, object: nil)
            XCTAssertEqual(try item().subtitleLabel.stringValue, "")
            instant = Date(timeIntervalSince1970: 1798761599)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            XCTAssertEqual(try item().subtitleLabel.stringValue, "2027")
            XCTAssertEqual(calendar.scrollView.contentView.bounds.origin, offset)
        }
        try calendar.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 3600)!))
        calendar.layoutSubtreeIfNeeded()
        XCTAssertEqual(try item().subtitleLabel.stringValue, "")
    }

    @MainActor func testLegacyCellContentAlignment() throws {
        _ = NSApplication.shared
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        let engine = try CalendarEngine(configuration: CalendarConfiguration())
        let occurrence = try XCTUnwrap(engine.grid(containing: day, scope: .month).occurrences.first { $0.day == day })
        let cell = FSCalendarItem()
        for (size, expectedDiameter) in [(CGSize(width: 116, height: 44), CGFloat(35)), (CGSize(width: 70, height: 60), CGFloat(125) / 3), (CGSize(width: 28, height: 32), CGFloat(80) / 3)] {
            cell.view.frame = CGRect(origin: .zero, size: size)
            for events in [0, 3] {
                for subtitle in [nil, "Lunar"] as [String?] {
                    for hasImage in [false, true] {
                        for stateFlags in [(false, false), (true, false), (false, true)] {
                            cell.apply(content: DayContent(subtitle: subtitle, image: hasImage ? NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) : nil, numberOfEvents: events),
                                       state: DayState(occurrence: occurrence, isSelected: stateFlags.0, isToday: stateFlags.1),
                                       appearance: FSCalendarAppearance(), style: DayAppearance(cornerRadius: 7))
                            cell.viewDidLayout()
                            let textFrame = subtitle == nil ? cell.titleLabel.frame : cell.titleLabel.frame.union(cell.subtitleLabel.frame)
                            XCTAssertEqual(cell.selectionBackground.frame.width, expectedDiameter, accuracy: 0.5)
                            XCTAssertEqual(textFrame.midY, cell.selectionBackground.frame.midY, accuracy: 0.5)
                            XCTAssertEqual(cell.selectionBackground.frame.midY, size.height * 5 / 12, accuracy: 0.5)
                            if !hasImage { XCTAssertEqual(cell.titleLabel.frame.midX, size.width / 2, accuracy: 0.5) }
                            XCTAssertEqual(cell.selectionBackground.layer!.cornerRadius, 7)
                            let dots = cell.view.subviews.filter { $0 !== cell.selectionBackground && !($0 is NSTextField) && !($0 is NSImageView) && !$0.isHidden }
                            XCTAssertEqual(dots.count, events)
                            for dot in dots { XCTAssertGreaterThan(dot.frame.minY, cell.selectionBackground.frame.maxY) }
                        }
                    }
                }
            }
        }
        cell.prepareForReuse()
        cell.apply(content: DayContent(), state: DayState(occurrence: occurrence, isSelected: false, isToday: false),
                   appearance: FSCalendarAppearance(), style: DayAppearance())
        cell.viewDidLayout()
        XCTAssertNil(cell.dayImageView.image)
        XCTAssertEqual(cell.titleLabel.frame.midY, cell.selectionBackground.frame.midY, accuracy: 0.5)
        XCTAssertEqual(cell.selectionBackground.frame.width, 80 / 3, accuracy: 0.5)
    }

    @MainActor func testCustomRegistrationFallbackReuseAndPlaceholderSelection() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let provider = ContentProvider(); view.dataSource = provider
        try view.register(CustomItem.self, forItemReuseIdentifier: "custom")
        XCTAssertThrowsError(try view.register(CustomItem.self, forItemReuseIdentifier: ""))
        let day = try CivilDay(year: 2024, month: 2, day: 29)
        try view.setCurrentPage(day); try view.select(day)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        func item() throws -> FSCalendarItem { try XCTUnwrap(view.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }.first { $0.dayState?.occurrence.day == day }) }
        let original = try item(); XCTAssertTrue(original is CustomItem)
        XCTAssertEqual(original.titleLabel.stringValue, "X"); XCTAssertNotNil(original.dayImageView.image)
        let identifier = original.view.accessibilityIdentifier()
        try view.navigate(1, animated: false); view.layoutSubtreeIfNeeded()
        let placeholder = try item()
        XCTAssertEqual(placeholder.dayState?.occurrence.position, .previous)
        XCTAssertEqual(placeholder.dayState?.isSelected, true)
        XCTAssertNotEqual(identifier, placeholder.view.accessibilityIdentifier())
        provider.custom = false; view.reload(dates: [day])
        XCTAssertEqual(placeholder.titleLabel.stringValue, "29")
        XCTAssertEqual(placeholder.subtitleLabel.stringValue, "")
        XCTAssertNil(placeholder.dayImageView.image)
        try view.deselect(day); XCTAssertEqual(placeholder.dayState?.isSelected, false)
        provider.identifier = "unknown"; view.reloadData(); view.layoutSubtreeIfNeeded()
        XCTAssertFalse(try item() is CustomItem)
    }
    @MainActor func testAccessibilitySelectionDisabledStateAndKeyboardExit() throws {
        _ = NSApplication.shared
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
        let day = try CivilDay(year: 2024, month: 2, day: 14)
        let configuration = try CalendarConfiguration(
            minimumDate: CivilDay(year: 2024, month: 2, day: 10),
            maximumDate: CivilDay(year: 2024, month: 2, day: 20),
            timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"))
        try view.apply(configuration: configuration); try view.setCurrentPage(day); view.today = day
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentView!.bounds), next = NSTextField(frame: NSRect(x: 0, y: 350, width: 100, height: 24))
        container.addSubview(view); container.addSubview(next); window.contentView = container
        window.orderFront(nil); defer { window.close() }
        view.layoutSubtreeIfNeeded()
        func dayView(_ value: CivilDay) throws -> NSView {
            try XCTUnwrap(view.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }.first { $0.dayState?.occurrence.day == value }?.view)
        }
        let cell = try dayView(day)
        XCTAssertEqual(cell.accessibilityLabel(), "Wednesday, February 14, 2024")
        XCTAssertTrue(cell.isAccessibilityEnabled())
        XCTAssertFalse(try dayView(day.addingDays(-5)).isAccessibilityEnabled())
        window.makeFirstResponder(view); try view.focus(day)
        XCTAssertTrue(cell.isAccessibilityFocused())
        XCTAssertEqual(cell.layer?.borderWidth, 0)
        // Exercise the same focus/selection path as a mouse click, then keyboard navigation.
        view.input.activate(day)
        XCTAssertEqual(cell.layer?.borderWidth, 0)
        XCTAssertTrue(cell.isAccessibilitySelected())
        let arrow = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
        view.keyDown(with: arrow)
        let following = try dayView(day.addingDays(1))
        XCTAssertEqual(view.focusedDay, try day.addingDays(1))
        XCTAssertTrue(following.isAccessibilityFocused())
        XCTAssertFalse(cell.isAccessibilityFocused())
        XCTAssertEqual(following.layer?.borderWidth, 0)
        try view.focus(day)
        try view.select(day)
        XCTAssertTrue(cell.isAccessibilitySelected())
        XCTAssertTrue((cell.accessibilityValue() as? String ?? "").contains("selected"))
        XCTAssertTrue((cell.accessibilityValue() as? String ?? "").contains("today"))
        view.nextKeyView = next
        let tab = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        view.keyDown(with: tab)
        XCTAssertFalse(window.firstResponder === view)
        XCTAssertFalse(view.hasKeyboardFocus); XCTAssertFalse(cell.isAccessibilityFocused())
        XCTAssertEqual(view.selectedDays, [day])
        try view.apply(configuration: CalendarConfiguration(minimumDate: configuration.minimumDate,
            maximumDate: configuration.maximumDate, timeZone: configuration.timeZone, locale: configuration.locale, selectionMode: .disabled))
        view.layoutSubtreeIfNeeded()
        let disabled = try dayView(day)
        XCTAssertFalse(disabled.isAccessibilityEnabled()); XCTAssertFalse(disabled.accessibilityPerformPress())
        XCTAssertTrue(view.selectedDays.isEmpty)
    }
    @MainActor func testViewReleasesItsControllersAndItems() {
        _ = NSApplication.shared
        weak var reference: FSCalendarView?
        autoreleasepool {
            let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 490, height: 340))
            view.layoutSubtreeIfNeeded(); reference = view
        }
        XCTAssertNil(reference)
    }
}
#endif
