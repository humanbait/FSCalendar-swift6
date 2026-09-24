import Foundation
import XCTest
@testable import FSCalendarCore

final class CalendarEngineTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> CivilDay {
        try CivilDay(year: year, month: month, day: day)
    }
    private func engine(firstWeekday: Int = 1, placeholders: PlaceholderMode = .sixRows,
                        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) throws -> CalendarEngine {
        try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: firstWeekday,
            placeholders: placeholders, timeZone: timeZone, locale: Locale(identifier: "en_US_POSIX")))
    }
    func testLeapYearValidation() throws {
        XCTAssertNoThrow(try day(2000, 2, 29))
        XCTAssertNoThrow(try day(2024, 2, 29))
        XCTAssertThrowsError(try day(1900, 2, 29))
        XCTAssertThrowsError(try day(2100, 2, 29))
        XCTAssertThrowsError(try day(2024, 4, 31))
        XCTAssertThrowsError(try day(2024, 0, 1))
    }
    func testConventionalAlignedSixRowsDoNotAddPrecedingWeek() throws {
        let grid = try engine().grid(containing: day(2024, 9, 1), scope: .month)
        XCTAssertEqual(grid.rowCount, 6)
        XCTAssertEqual(grid.occurrences.count, 42)
        XCTAssertEqual(grid.occurrences.first?.day, try day(2024, 9, 1))
        XCTAssertEqual(grid.occurrences.last?.day, try day(2024, 10, 12))
    }
    func testFourFiveAndSixRowMonths() throws {
        let e = try engine(placeholders: .variable)
        XCTAssertEqual(try e.grid(containing: day(2015, 2, 1), scope: .month).rowCount, 4)
        XCTAssertEqual(try e.grid(containing: day(2024, 2, 1), scope: .month).rowCount, 5)
        XCTAssertEqual(try e.grid(containing: day(2024, 3, 1), scope: .month).rowCount, 6)
    }
    func testHiddenPlaceholdersPreserveWeekdaySlots() throws {
        let grid = try engine(placeholders: .none).grid(containing: day(2024, 2, 1), scope: .month)
        XCTAssertEqual(grid.occurrences.filter { !$0.isHidden }.count, 29)
        XCTAssertEqual(grid.occurrences[4].day, try day(2024, 2, 1))
        XCTAssertTrue(grid.occurrences[0].isHidden)
        XCTAssertFalse(grid.occurrences[0].isSelectable)
    }
    func testEveryFirstWeekdayAndDateIndexRoundTrip() throws {
        for weekday in 1...7 {
            let e = try engine(firstWeekday: weekday)
            for year in 2023...2025 {
                for month in 1...12 {
                    let grid = try e.grid(containing: day(year, month, 1), scope: .month)
                    XCTAssertEqual(grid.occurrences[0].day.weekday, weekday)
                    for (index, occurrence) in grid.occurrences.enumerated() {
                        XCTAssertEqual(e.index(of: occurrence.day, in: grid), index)
                        XCTAssertEqual(occurrence.id.page, grid.id)
                    }
                }
            }
        }
    }
    func testWeekCrossesYearBoundary() throws {
        let grid = try engine().grid(containing: day(2024, 12, 31), scope: .week)
        XCTAssertEqual(grid.id.anchor, try day(2024, 12, 29))
        XCTAssertEqual(grid.occurrences.last?.day, try day(2025, 1, 4))
        XCTAssertEqual(grid.rowCount, 1)
    }
    func testOccurrenceIdentityDiffersAcrossMonthPages() throws {
        let e = try engine()
        let date = try day(2024, 2, 29)
        let february = try e.grid(containing: date, scope: .month)
        let march = try e.grid(containing: day(2024, 3, 1), scope: .month)
        let a = try XCTUnwrap(february.occurrences.first { $0.day == date })
        let b = try XCTUnwrap(march.occurrences.first { $0.day == date })
        XCTAssertEqual(a.day, b.day)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(b.position, .previous)
    }
    func testDSTPreservesCivilDaysAcrossShortAndLongDays() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let before = try day(2024, 3, 10), after = try day(2024, 3, 11)
        XCTAssertEqual(try after.date(in: zone).timeIntervalSince(before.date(in: zone)), 23 * 3600, accuracy: 1)
        let fall = try day(2024, 11, 3), next = try day(2024, 11, 4)
        XCTAssertEqual(try next.date(in: zone).timeIntervalSince(fall.date(in: zone)), 25 * 3600, accuracy: 1)
        let grid = try engine(timeZone: zone).grid(containing: before, scope: .month)
        XCTAssertEqual(Set(grid.occurrences.map(\.day)).count, 42)
    }
    func testSkippedCivilDayIsDisplayedButNotSelectable() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Pacific/Apia"))
        let skipped = try day(2011, 12, 30)
        XCTAssertThrowsError(try skipped.date(in: zone)) { error in
            XCTAssertEqual(error as? CalendarError, .nonexistentDay(skipped))
        }
        let e = try engine(timeZone: zone)
        let grid = try e.grid(containing: day(2011, 12, 1), scope: .month)
        let occurrence = try XCTUnwrap(grid.occurrences.first { $0.day == skipped })
        XCTAssertFalse(occurrence.isSelectable)
        XCTAssertEqual(skipped.weekday, 6)
    }
    func testInclusiveBoundsAndSectionRoundTrips() throws {
        let minimum = try day(2024, 2, 10), maximum = try day(2024, 3, 20)
        let e = try CalendarEngine(configuration: CalendarConfiguration(minimumDate: minimum, maximumDate: maximum))
        XCTAssertTrue(e.isSelectable(minimum))
        XCTAssertTrue(e.isSelectable(maximum))
        XCTAssertFalse(try e.isSelectable(day(2024, 2, 9)))
        XCTAssertEqual(e.pageCount(scope: .month), 2)
        for scope in [CalendarScope.month, .week] {
            for index in 0..<e.pageCount(scope: scope) {
                let page = try e.page(at: index, scope: scope)
                XCTAssertEqual(try e.sectionIndex(for: page.anchor, scope: scope), index)
            }
        }
    }
    func testContinuousMonthsOwnEveryDayOnceForAllWeekdaysAndPlaceholderModes() throws {
        let minimum = try day(2023, 12, 15), maximum = try day(2025, 3, 20)
        for weekday in 1...7 {
            var expectedGrids: [CalendarGrid]?
            var expectedSections: [ContinuousMonthSection]?
            for placeholders: PlaceholderMode in [.none, .variable, .sixRows] {
                let e = try CalendarEngine(configuration: CalendarConfiguration(firstWeekday: weekday,
                    placeholders: placeholders, minimumDate: minimum, maximumDate: maximum,
                    timeZone: TimeZone(secondsFromGMT: 0)!))
                let sections = e.continuousMonthSections()
                let grids = try sections.map { try e.continuousMonthGrid(containing: $0.page.anchor) }
                if let expectedGrids { XCTAssertEqual(grids, expectedGrids) }
                if let expectedSections { XCTAssertEqual(sections, expectedSections) }
                expectedGrids = grids; expectedSections = sections
                let days = grids.flatMap { $0.occurrences.map(\.day) }
                XCTAssertEqual(Set(days).count, days.count)
                XCTAssertEqual(days.first, minimum.startOfMonth)
                XCTAssertEqual(days.last, try day(2025, 3, 31))
                for (a, b) in zip(days, days.dropFirst()) { XCTAssertEqual(a.distance(to: b), 1) }
                for (section, grid) in zip(sections, grids) {
                    XCTAssertEqual(grid.occurrences.count, section.dayCount)
                    XCTAssertEqual(grid.rowCount, section.rowCount)
                    XCTAssertEqual(section.dayCount, section.page.anchor.daysInMonth)
                    for (index, occurrence) in grid.occurrences.enumerated() {
                        XCTAssertEqual(occurrence.position, .current)
                        XCTAssertFalse(occurrence.isHidden)
                        XCTAssertEqual(occurrence.id.page.anchor, occurrence.day.startOfMonth)
                        XCTAssertEqual(e.index(of: occurrence.day, in: grid), index)
                        XCTAssertEqual((section.startSlot + index) % 7, (occurrence.day.weekday - weekday + 7) % 7)
                        XCTAssertEqual(occurrence.isSelectable, occurrence.day >= minimum && occurrence.day <= maximum)
                    }
                }
                for (a, b) in zip(sections, sections.dropFirst()) {
                    XCTAssertEqual(a.startSlot + a.dayCount, b.startSlot)
                }
                XCTAssertEqual(grids.first { $0.id.anchor == (try? day(2024, 2, 1)) }?.occurrences.count, 29)
            }
        }
    }
    func testContinuousMonthsPreserveSkippedCivilDaySlotsAndBounds() throws {
        let skipped = try day(2011, 12, 30)
        let e = try CalendarEngine(configuration: CalendarConfiguration(minimumDate: day(2011, 12, 29),
            maximumDate: day(2011, 12, 31), timeZone: TimeZone(identifier: "Pacific/Apia")!))
        let grid = try e.continuousMonthGrid(containing: skipped)
        XCTAssertEqual(grid.occurrences.count, 31)
        XCTAssertFalse(grid.occurrences[29].isSelectable)
        XCTAssertFalse(grid.occurrences[29].isHidden)
        XCTAssertEqual(grid.occurrences.filter(\.isSelectable).map(\.day), [try day(2011, 12, 29), try day(2011, 12, 31)])
        for year in [1, 9999] {
            let boundary = try day(year, year == 1 ? 1 : 12, 1)
            let bounded = try CalendarEngine(configuration: CalendarConfiguration(minimumDate: boundary,
                maximumDate: boundary, timeZone: TimeZone(secondsFromGMT: 0)!))
            XCTAssertEqual(bounded.continuousMonthSections().count, 1)
            XCTAssertEqual(try bounded.continuousMonthGrid(containing: boundary).occurrences.count, 31)
        }
    }
    func testInvalidConfigurationIsRejected() throws {
        XCTAssertThrowsError(try CalendarConfiguration(firstWeekday: 0))
        XCTAssertThrowsError(try CalendarConfiguration(firstWeekday: 8))
        XCTAssertThrowsError(try CalendarConfiguration(minimumDate: day(2025, 1, 1), maximumDate: day(2024, 1, 1)))
    }
    func testExtremeArithmeticThrowsInsteadOfOverflowing() throws {
        XCTAssertThrowsError(try day(1900, 1, 1).addingDays(Int.max))
        XCTAssertThrowsError(try day(2024, 1, 1).addingDays(Int.min))
        XCTAssertThrowsError(try day(2024, 1, 1).addingMonths(Int.max))
    }
}
