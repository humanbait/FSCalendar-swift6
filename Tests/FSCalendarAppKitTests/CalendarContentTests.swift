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
final class CalendarContentTests: XCTestCase {
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
