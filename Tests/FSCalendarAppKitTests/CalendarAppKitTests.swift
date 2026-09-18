#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest
@testable import FSCalendarAppKit

final class CalendarAppKitTests: XCTestCase {
    @MainActor func testProgrammaticInitialization() {
        let view = FSCalendarView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
        XCTAssertEqual(view.frame.width, 480)
    }
}
#endif
