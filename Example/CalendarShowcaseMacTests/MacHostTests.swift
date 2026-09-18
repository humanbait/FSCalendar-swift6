import AppKit
import XCTest
@testable import FSCalendarAppKit
@testable import CalendarShowcaseMac

final class MacHostTests: XCTestCase {
    @MainActor func testShowcaseHitTesting() throws {
        let controller = ShowcaseController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = controller; window.orderFront(nil)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let calendar = controller.driver.calendar
        let item = try XCTUnwrap(calendar.collectionView.visibleItems().compactMap { $0 as? FSCalendarItem }.first { $0.dayState?.occurrence.day.day == 14 })
        let center = item.view.convert(NSPoint(x: item.view.bounds.midX, y: item.view.bounds.midY), to: controller.view.superview)
        let hit = controller.view.hitTest(center)
        XCTAssertTrue(hit === item.view)
        controller.show(.dark)
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        controller.show(.month)
        XCTAssertNil(window.appearance)
    }
    @MainActor func testCalendarHostedInWindow() {
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(view.window === window)
    }
}
