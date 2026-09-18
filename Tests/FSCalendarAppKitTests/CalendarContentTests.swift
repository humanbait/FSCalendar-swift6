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
