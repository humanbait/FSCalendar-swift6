import AppKit
import XCTest
import FSCalendarAppKit

final class MacHostTests: XCTestCase {
    @MainActor func testCalendarHostedInWindow() {
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view; window.orderFront(nil)
        defer { window.close() }
        XCTAssertTrue(view.window === window)
    }
}
