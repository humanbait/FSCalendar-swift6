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
        XCUIElement.perform(withKeyModifiers: [.command]) { day.click() }
        XCTAssertTrue((readout.value as? String ?? "").hasSuffix("selected: 2024-02-15,2024-02-14"))
        XCUIElement.perform(withKeyModifiers: [.shift]) { day.click() }
        XCTAssertTrue((readout.value as? String ?? "").hasSuffix("selected: 2024-02-15"))
        let beforeTab = readout.value as? String
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(readout.value as? String, beforeTab, "Moving focus must not change selection")
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
    @MainActor func testDragScrollingTransitionsAndWindowResize() {
        let app = XCUIApplication(); app.launchArguments = ["--scenario", "swipe"]; app.launch()
        let first = app.buttons["day.2024-02-12.1.2024-02-01"], last = app.buttons["day.2024-02-15.1.2024-02-01"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click(forDuration: 0.2, thenDragTo: last)
        let state = app.textFields["state.readout"]
        expectation(for: NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", "2024-02-12", "2024-02-15"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        app.buttons["scenario.month"].click()
        app.scrollViews["calendar.scroll"].scroll(byDeltaX: -160, deltaY: 0)
        expectation(for: NSPredicate(format: "value CONTAINS %@", "2024-03-01"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        app.buttons["scenario.scope"].click()
        app.scrollViews["agenda"].scroll(byDeltaX: 0, deltaY: -150)
        XCTAssertTrue((state.value as? String ?? "").contains("• month"))
        let handle = app.buttons["scope.handle"]
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -190)))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "• week"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        for _ in 0..<3 {
            app.buttons["scope.toggle"].click()
            expectation(for: NSPredicate(format: "value CONTAINS %@", "• month"), evaluatedWith: state); waitForExpectations(timeout: 5)
            app.buttons["scope.toggle"].click()
            expectation(for: NSPredicate(format: "value CONTAINS %@", "• week"), evaluatedWith: state); waitForExpectations(timeout: 5)
        }
        let originalWidth = app.windows.firstMatch.frame.width
        let corner = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -100, dy: -70)))
        XCTAssertLessThan(app.windows.firstMatch.frame.width, originalWidth)
        XCTAssertTrue((state.value as? String ?? "").contains("• week"))
        app.buttons["reset"].click()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "• month"), evaluatedWith: state); waitForExpectations(timeout: 5)
    }
    @MainActor func testLaunchMeasurement() {
        let app = XCUIApplication()
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) { app.launch() }
    }
    @MainActor func testShowcaseLaunches() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.popUpButtons["scenario.selector"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reset"].exists)
    }
}
