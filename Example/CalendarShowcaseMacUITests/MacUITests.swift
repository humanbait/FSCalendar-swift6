import XCTest

final class MacUITests: XCTestCase {
    @MainActor func testMouseToggleAndKeyboardFocus() {
        let app = XCUIApplication(); app.launch()
        let day = app.buttons["day.2024-02-14.1.2024-02-01"]
        XCTAssertTrue(day.waitForExistence(timeout: 10)); day.click()
        let readout = app.textFields["state.readout"]
        let selected = NSPredicate(format: "value CONTAINS %@", "selected: 2024-02-14")
        expectation(for: selected, evaluatedWith: readout); waitForExpectations(timeout: 5)
        day.click()
        XCTAssertFalse((readout.value as? String ?? "").contains("selected: 2024-02-14"))
        app.typeKey(.rightArrow, modifierFlags: []); app.typeKey(.space, modifierFlags: [])
        expectation(for: NSPredicate(format: "value CONTAINS %@", "selected: 2024-02-15"), evaluatedWith: readout)
        waitForExpectations(timeout: 5)
    }
    @MainActor func testShowcaseLaunches() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.popUpButtons["scenario.selector"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reset"].exists)
    }
}
