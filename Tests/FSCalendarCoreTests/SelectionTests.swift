import XCTest
@testable import FSCalendarCore

final class SelectionTests: XCTestCase {
    private let a = try! CivilDay(year: 2024, month: 2, day: 12)
    private let b = try! CivilDay(year: 2024, month: 2, day: 14)
    func testOrderedSelectionDeduplicatesAndNoOpsHaveNoChange() throws {
        var state = SelectionState()
        let e = try CalendarEngine(configuration: CalendarConfiguration(selectionMode: .multiple))
        let first = try XCTUnwrap(state.propose([b, a, b], engine: e, origin: .programmatic))
        XCTAssertEqual(first.added, [b, a])
        XCTAssertEqual(first.selection, [b, a])
        state.commit(first)
        XCTAssertNil(try state.propose([b, a], engine: e, origin: .programmatic))
        XCTAssertTrue(state.contains(a))
        XCTAssertEqual(state.latest, a)
    }
    func testSingleSelectionReplacementIsAtomic() throws {
        var state = SelectionState()
        let e = try CalendarEngine(configuration: CalendarConfiguration())
        state.commit(try XCTUnwrap(state.propose([a], engine: e, origin: .user)))
        let change = try XCTUnwrap(state.propose([b], engine: e, origin: .user))
        XCTAssertEqual(state.days, [a]) // Proposal does not mutate; veto can reject it.
        XCTAssertEqual(change.added, [b])
        XCTAssertEqual(change.removed, [a])
        state.commit(change)
        XCTAssertEqual(state.days, [b])
    }
    func testInvalidTransactionsLeaveStateUnchanged() throws {
        var state = SelectionState()
        let e = try CalendarEngine(configuration: CalendarConfiguration())
        state.commit(try XCTUnwrap(state.propose([a], engine: e, origin: .programmatic)))
        XCTAssertThrowsError(try state.propose([a, b], engine: e, origin: .programmatic))
        let outside = try CivilDay(year: 1900, month: 1, day: 1)
        XCTAssertThrowsError(try state.propose([outside], engine: e, origin: .programmatic))
        XCTAssertEqual(state.days, [a])
        let disabled = try CalendarEngine(configuration: CalendarConfiguration(selectionMode: .disabled))
        XCTAssertThrowsError(try state.propose([b], engine: disabled, origin: .user))
    }
    func testConfigurationPruningRetainsLatestInRangeSelection() throws {
        var state = SelectionState()
        let multiple = try CalendarEngine(configuration: CalendarConfiguration(selectionMode: .multiple))
        state.commit(try XCTUnwrap(state.propose([b, a], engine: multiple, origin: .programmatic)))
        let single = try CalendarEngine(configuration: CalendarConfiguration())
        let change = try XCTUnwrap(state.pruningChange(for: single))
        XCTAssertEqual(change.selection, [a])
        XCTAssertEqual(change.origin, .configuration)
        state.commit(change)
        let bounded = try CalendarEngine(configuration: CalendarConfiguration(minimumDate: b))
        XCTAssertEqual(state.pruningChange(for: bounded)?.selection, [])
    }
}
