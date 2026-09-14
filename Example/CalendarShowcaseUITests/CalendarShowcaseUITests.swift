import XCTest

final class CalendarShowcaseUITests: XCTestCase {
    // Xcode 27's device runner can disconnect during inter-test attachment cleanup on iOS 17.
    // Keep the unchanged scenario assertions in one test, with individually named result activities.
    @MainActor func testLegacyScenarioMatrix() {
        XCTContext.runActivity(named: "TapAndReset") { _ in exerciseTapAndReset() }
        XCTContext.runActivity(named: "PagingAndSelectionPersistence") { _ in exercisePagingAndSelectionPersistence() }
        XCTContext.runActivity(named: "ScopeChangesAndRotation") { _ in exerciseScopeChangesAndRotation() }
        XCTContext.runActivity(named: "MultipleSelectionAndCustomCells") { _ in exerciseMultipleSelectionAndCustomCells() }
        XCTContext.runActivity(named: "SwipeSelection") { _ in exerciseSwipeSelection() }
        XCTContext.runActivity(named: "ContinuousScroll") { _ in exerciseContinuousScroll() }
        XCTContext.runActivity(named: "VerticalPaging") { _ in exerciseVerticalPaging() }
        XCTContext.runActivity(named: "InteractiveScopeRoundTrip") { _ in exerciseInteractiveScopeRoundTrip() }
        XCTContext.runActivity(named: "BoundsRejectDisabledDay") { _ in exerciseBoundsRejectDisabledDay() }
        XCTContext.runActivity(named: "AppearanceScenarios") { _ in exerciseAppearanceScenarios() }
        XCTContext.runActivity(named: "LaunchPerformance") { _ in exerciseLaunchPerformance() }
    }
    @MainActor private func launch(_ scenario: String, implementation: String = "legacy") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--scenario", scenario, "--implementation", implementation]
        app.launch()
        XCTAssertTrue(app.staticTexts["page-state"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func wait(_ element: XCUIElement, contains text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "Expected \(text); actual state: \(element.label)")
    }
    @MainActor private func day(_ app: XCUIApplication, _ date: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "day.\(date).1.")).firstMatch
    }
    @MainActor private func exerciseTapAndReset() {
        let app = launch("month")
        let cell = day(app, "2024-02-14")
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        wait(app.staticTexts["selection-state"], contains: "2024-02-14")
        app.buttons["reset"].tap()
        wait(app.staticTexts["selection-state"], contains: "none")
    }
    @MainActor private func exercisePagingAndSelectionPersistence() {
        let app = launch("multiple")
        day(app, "2024-02-14").tap()
        app.buttons["next"].tap()
        wait(app.staticTexts["page-state"], contains: "2024-03")
        app.buttons["previous"].tap()
        wait(app.staticTexts["page-state"], contains: "2024-02")
        wait(app.staticTexts["selection-state"], contains: "2024-02-14")
    }
    @MainActor private func exerciseScopeChangesAndRotation() {
        let app = launch("scope")
        app.buttons["scope"].tap()
        wait(app.staticTexts["page-state"], contains: "week")
        app.buttons["scope"].tap()
        wait(app.staticTexts["page-state"], contains: "month")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["next"].exists)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["next"].tap()
        wait(app.staticTexts["page-state"], contains: "2024-03")
    }
    @MainActor private func exerciseMultipleSelectionAndCustomCells() {
        let app = launch("range")
        day(app, "2024-02-12").tap()
        day(app, "2024-02-14").tap()
        wait(app.staticTexts["selection-state"], contains: "2024-02-13")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "legacy-range"
        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor private func exerciseSwipeSelection() {
        let app = launch("swipe")
        let start = day(app, "2024-02-12")
        let end = day(app, "2024-02-15")
        start.press(forDuration: 0.9, thenDragTo: end)
        wait(app.staticTexts["selection-state"], contains: "2024-02-15")
    }
    @MainActor private func exerciseContinuousScroll() {
        let app = launch("continuous")
        wait(app.staticTexts["page-state"], contains: "2024-02")
        let before = app.staticTexts["page-state"].label
        app.collectionViews["calendar-grid"].swipeUp()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: app.staticTexts["page-state"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    @MainActor private func exerciseVerticalPaging() {
        let app = launch("vertical")
        app.collectionViews["calendar-grid"].swipeUp()
        wait(app.staticTexts["page-state"], contains: "2024-03")
    }
    @MainActor private func exerciseInteractiveScopeRoundTrip() {
        let app = launch("scope")
        app.collectionViews["calendar-grid"].swipeUp()
        wait(app.staticTexts["page-state"], contains: "week")
        app.collectionViews["calendar-grid"].swipeDown()
        wait(app.staticTexts["page-state"], contains: "month")
    }
    @MainActor private func exerciseBoundsRejectDisabledDay() {
        let app = launch("bounds")
        day(app, "2024-02-08").tap()
        wait(app.staticTexts["selection-state"], contains: "none")
        day(app, "2024-02-14").tap()
        wait(app.staticTexts["selection-state"], contains: "2024-02-14")
    }
    @MainActor private func exerciseAppearanceScenarios() {
        for scenario in ["content", "rtl", "largeText", "dark", "dynamicHeight"] {
            let app = launch(scenario)
            XCTAssertTrue(day(app, "2024-02-14").exists, scenario)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "legacy-\(scenario)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    @MainActor private func exerciseLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
