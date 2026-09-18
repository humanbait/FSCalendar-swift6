import XCTest

final class MacUITests: XCTestCase {
    @MainActor func testShowcaseLaunches() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.popUpButtons["scenario.selector"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reset"].exists)
    }
}
