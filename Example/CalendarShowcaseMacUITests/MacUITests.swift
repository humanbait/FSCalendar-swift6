import XCTest

final class MacUITests: XCTestCase {
    @MainActor func testMouseToggleAndKeyboardFocus() {
        let app = XCUIApplication(); app.launchArguments = ["--scenario", "multiple"]; app.launch()
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
    @MainActor func testAllScenarioScreensAndReset() {
        let app = XCUIApplication(); app.launch()
        let names = ["month", "vertical", "week", "continuous", "multiple", "swipe", "hidden", "variable", "sixRows", "bounds", "content", "custom", "range", "scope", "dynamicHeight", "rtl", "largeText", "dark"]
        for name in names {
            XCTContext.runActivity(named: "AppKit scenario: \(name)") { activity in
                let button = app.buttons["scenario.\(name)"]
                XCTAssertTrue(button.waitForExistence(timeout: 5)); button.click()
                let page = name == "week" ? "2024-02-11" : "2024-02-01"
                let day = app.buttons["day.2024-02-14.1.\(page)"]
                XCTAssertTrue(day.waitForExistence(timeout: 5)); day.click()
                let readout = app.textFields["state.readout"]
                expectation(for: NSPredicate(format: "value CONTAINS %@", "selected: 2024-02-14"), evaluatedWith: readout)
                waitForExpectations(timeout: 5)
                app.buttons["reload"].click()
                XCTAssertTrue((readout.value as? String ?? "").contains("selected: 2024-02-14"))
                let image = XCTAttachment(screenshot: app.screenshot()); image.name = "appkit-\(name)"; image.lifetime = .keepAlways; activity.add(image)
                app.buttons["reset"].click()
                XCTAssertFalse((readout.value as? String ?? "").contains("selected: 2024-02-14"))
            }
        }
    }
    @MainActor func testShowcaseLaunches() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.popUpButtons["scenario.selector"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reset"].exists)
    }
}
