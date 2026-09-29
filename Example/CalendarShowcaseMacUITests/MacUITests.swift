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
        let names = ["month", "vertical", "week", "continuous", "multiple", "swipe", "hidden", "variable", "sixRows", "bounds", "content", "custom", "range", "connectedRange", "scope", "dynamicHeight", "rtl", "largeText", "dark"]
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
    @MainActor func testConnectedRangeBandsAndExtension() {
        checkConnectedRangeBandsAndExtension(interfaceStyle: "Light")
    }
    @MainActor func testConnectedRangeBandsAndExtensionDark() {
        checkConnectedRangeBandsAndExtension(interfaceStyle: "Dark")
    }
    @MainActor private func checkConnectedRangeBandsAndExtension(interfaceStyle: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--scenario", "connectedRange"]
        app.launchEnvironment["FSCALENDAR_TEST_APPEARANCE"] = interfaceStyle.lowercased()
        app.launch()
        let readout = app.textFields["state.readout"]
        XCTAssertFalse(app.buttons["scope.handle"].isHittable)
        func click(_ date: String) {
            let month = String(date.prefix(7)) + "-01"
            let day = app.buttons["day.\(date).1.\(month)"]
            XCTAssertTrue(day.waitForExistence(timeout: 5))
            day.click()
        }
        func waitFor(_ date: String) {
            expectation(for: NSPredicate(format: "value CONTAINS %@", date), evaluatedWith: readout)
            waitForExpectations(timeout: 5)
        }
        click("2024-02-16"); click("2024-02-20")
        waitFor("2024-02-18")
        let heightComparison = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        heightComparison.name = "appkit-connected-range-today-height-\(interfaceStyle.lowercased())"
        heightComparison.lifetime = .keepAlways
        add(heightComparison)
        click("2024-02-14"); waitFor("2024-02-15")
        click("2024-02-22"); waitFor("2024-02-21")
        let beforeInsideTap = readout.value as? String
        click("2024-02-19")
        XCTAssertEqual(readout.value as? String, beforeInsideTap)
        click("2024-02-29"); click("2024-03-01"); waitFor("2024-03-01")
        XCTAssertFalse(app.staticTexts["calendar.heading"].exists)
        XCTAssertFalse(app.textFields["calendar.heading"].exists)
        let february = app.buttons["day.2024-02-29.1.2024-02-01"]
        let march = app.buttons["day.2024-03-01.1.2024-03-01"]
        XCTAssertTrue((february.value as? String ?? "").contains("Has events"))
        XCTAssertTrue((march.value as? String ?? "").contains("Has events"))
        XCTAssertEqual(february.frame.minY, march.frame.minY, accuracy: 1)
        XCTAssertEqual(february.frame.maxX, march.frame.minX, accuracy: 1)
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = "appkit-connected-range-continuous-\(interfaceStyle.lowercased())"
        image.lifetime = .keepAlways
        add(image)
        let beforeScroll = readout.value as? String ?? ""
        app.scrollViews["calendar.scroll"].scroll(byDeltaX: 0, deltaY: -400)
        expectation(for: NSPredicate(format: "value != %@", beforeScroll), evaluatedWith: readout)
        waitForExpectations(timeout: 5)
        XCTAssertTrue((readout.value as? String ?? "").contains("• month"))
        XCTAssertTrue((readout.value as? String ?? "").contains("2024-02-21"))
        app.buttons["scope.toggle"].click()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "• week"), evaluatedWith: readout)
        waitForExpectations(timeout: 5)
        app.scrollViews["calendar.scroll"].scroll(byDeltaX: 0, deltaY: -150)
        XCTAssertTrue((readout.value as? String ?? "").contains("• week"))
        app.buttons["scope.toggle"].click()
        expectation(for: NSPredicate(format: "value CONTAINS %@", "• month"), evaluatedWith: readout)
        waitForExpectations(timeout: 5)
        XCTAssertTrue((readout.value as? String ?? "").contains("2024-02-21"))
        let roundTrip = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        roundTrip.name = "appkit-connected-range-scope-round-trip-\(interfaceStyle.lowercased())"
        roundTrip.lifetime = .keepAlways
        add(roundTrip)
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
