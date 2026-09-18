import XCTest
@testable import FSCalendarCore

final class TransitionPlannerTests: XCTestCase {
    func testAnchorPriorityAndDestination() throws {
        let engine = try CalendarEngine(configuration: CalendarConfiguration())
        let first = try CivilDay(year: 2024, month: 2, day: 1)
        let today = try first.addingDays(13), selected = try first.addingDays(19)
        let visible = [first, today, selected]
        let plan = CalendarTransitionPlan(engine: engine, currentPage: first, visibleDays: visible,
            selectedDays: [first, selected], today: today, targetMode: .week)
        XCTAssertEqual(plan.anchor, selected)
        XCTAssertEqual(plan.destinationPage, engine.pageID(containing: selected, scope: .week).anchor)
        XCTAssertEqual(CalendarTransitionPlan(engine: engine, currentPage: first, visibleDays: visible,
            selectedDays: [], today: today, targetMode: .week).anchor, today)
        XCTAssertEqual(CalendarTransitionPlan(engine: engine, currentPage: first, visibleDays: visible.reversed(),
            selectedDays: [], today: nil, targetMode: .week).anchor, first)
    }
    func testOutOfBoundsVisibleDaysAreExcludedAndFallbackClamped() throws {
        let minimum = try CivilDay(year: 2024, month: 2, day: 10)
        let engine = try CalendarEngine(configuration: CalendarConfiguration(minimumDate: minimum))
        let outside = try minimum.addingDays(-9)
        let plan = CalendarTransitionPlan(engine: engine, currentPage: outside, visibleDays: [outside],
            selectedDays: [outside], today: outside, targetMode: .month(.vertical))
        XCTAssertEqual(plan.anchor, minimum)
        XCTAssertEqual(plan.destinationPage, minimum.startOfMonth)
    }
}
