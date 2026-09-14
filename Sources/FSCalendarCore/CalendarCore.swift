import Foundation

public enum CalendarError: Error, Equatable, Sendable {
    case invalidDay
    case invalidConfiguration(String)
    case nonexistentDay(CivilDay)
    case outOfBounds(CivilDay)
    case invalidPageIndex(Int)
    case selectionDisabled
    case multipleSelectionNotAllowed
    case selectionVetoed
    case reentrantMutation
    case unsupportedDisplayMode
}

/// A Gregorian civil date, independent of an instant or the page on which it is displayed.
public struct CivilDay: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else {
            throw CalendarError.invalidDay
        }
        self.year = year; self.month = month; self.day = day
    }
    public init(date: Date, timeZone: TimeZone = .current) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, let month = parts.month, let day = parts.day else {
            throw CalendarError.invalidDay
        }
        try self.init(year: year, month: month, day: day)
    }
    private init(uncheckedYear year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var startOfMonth: Self { Self(uncheckedYear: year, month: month, day: 1) }
    public var daysInMonth: Int { Self.daysInMonth(year: year, month: month) }
    /// Foundation weekday numbering: Sunday = 1, Saturday = 7.
    public var weekday: Int { Self.modulo(ordinal + 4, 7) + 1 }

    /// Resolves the first valid instant in this civil day. Skipped days are rejected, never normalized silently.
    public func date(in timeZone: TimeZone = .current) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(era: year > 0 ? 1 : 0, year: year > 0 ? year : 1 - year,
                                   month: month, day: day, hour: 12)
        guard let noon = calendar.date(from: parts) else { throw CalendarError.nonexistentDay(self) }
        let start = calendar.startOfDay(for: noon)
        let actual = calendar.dateComponents([.era, .year, .month, .day], from: start)
        guard actual.year == parts.year, actual.era == parts.era, actual.month == month, actual.day == day else {
            throw CalendarError.nonexistentDay(self)
        }
        return start
    }
    public func addingDays(_ count: Int) throws -> Self {
        let (next, overflow) = ordinal.addingReportingOverflow(count)
        guard !overflow, next >= Self(uncheckedYear: 1, month: 1, day: 1).ordinal,
              next <= Self(uncheckedYear: 9999, month: 12, day: 31).ordinal else { throw CalendarError.invalidDay }
        let result = Self(ordinal: next)
        guard (1...9999).contains(result.year) else { throw CalendarError.invalidDay }
        return result
    }
    public func addingMonths(_ count: Int) throws -> Self {
        let (total, overflow) = (year * 12 + month - 1).addingReportingOverflow(count)
        guard !overflow, (12..<(10000 * 12)).contains(total) else { throw CalendarError.invalidDay }
        let year = total / 12, month = total % 12 + 1
        return try Self(year: year, month: month, day: min(day, Self.daysInMonth(year: year, month: month)))
    }
    public func distance(to other: Self) -> Int { other.ordinal - ordinal }

    // Gregorian civil arithmetic keeps weekday slots stable even when a time zone skips a whole day.
    var ordinal: Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let shiftedMonth = month + (month > 2 ? -3 : 9)
        let doy = (153 * shiftedMonth + 2) / 5 + day - 1
        return era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
    }
    init(ordinal: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp + (mp < 10 ? 3 : -9)
        self.init(uncheckedYear: y + (month <= 2 ? 1 : 0), month: month, day: day)
    }
    static func modulo(_ value: Int, _ divisor: Int) -> Int { (value % divisor + divisor) % divisor }
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

public enum CalendarScope: String, Hashable, Sendable { case month, week }
public enum PlaceholderMode: String, Hashable, Sendable { case none, variable, sixRows }
public enum SelectionMode: String, Hashable, Sendable { case disabled, single, multiple }
public enum MonthPosition: Int, Hashable, Sendable { case previous = 0, current = 1, next = 2 }
public enum SelectionOrigin: String, Hashable, Sendable { case user, programmatic, configuration }

public struct CalendarConfiguration: Hashable, Sendable {
    public let firstWeekday: Int
    public let placeholders: PlaceholderMode
    public let minimumDate: CivilDay
    public let maximumDate: CivilDay
    public let timeZone: TimeZone
    public let locale: Locale
    public let selectionMode: SelectionMode

    public init(firstWeekday: Int = 1, placeholders: PlaceholderMode = .sixRows,
                minimumDate: CivilDay = try! CivilDay(year: 1970, month: 1, day: 1),
                maximumDate: CivilDay = try! CivilDay(year: 2099, month: 12, day: 31),
                timeZone: TimeZone = .current, locale: Locale = .current,
                selectionMode: SelectionMode = .single) throws {
        guard (1...7).contains(firstWeekday) else { throw CalendarError.invalidConfiguration("firstWeekday must be 1...7") }
        guard minimumDate <= maximumDate else { throw CalendarError.invalidConfiguration("minimumDate exceeds maximumDate") }
        self.firstWeekday = firstWeekday; self.placeholders = placeholders
        self.minimumDate = minimumDate; self.maximumDate = maximumDate
        self.timeZone = timeZone; self.locale = locale; self.selectionMode = selectionMode
        _ = try minimumDate.date(in: timeZone)
        _ = try maximumDate.date(in: timeZone)
    }
}

public struct PageID: Hashable, Sendable {
    public let anchor: CivilDay
    public let scope: CalendarScope
    public init(anchor: CivilDay, scope: CalendarScope) { self.anchor = anchor; self.scope = scope }
}
public struct CellOccurrenceID: Hashable, Sendable {
    public let page: PageID
    public let day: CivilDay
    public init(page: PageID, day: CivilDay) { self.page = page; self.day = day }
}
public struct DayOccurrence: Hashable, Sendable {
    public let id: CellOccurrenceID
    public let position: MonthPosition
    public let isHidden: Bool
    public let isSelectable: Bool
    public var day: CivilDay { id.day }
}
public struct CalendarGrid: Hashable, Sendable {
    public let id: PageID
    public let rowCount: Int
    public let occurrences: [DayOccurrence]
}

public struct CalendarEngine: Sendable {
    public let configuration: CalendarConfiguration
    public init(configuration: CalendarConfiguration) throws { self.configuration = configuration }

    public func pageID(containing day: CivilDay, scope: CalendarScope) -> PageID {
        let anchor = scope == .month ? day.startOfMonth
            : CivilDay(ordinal: day.ordinal - CivilDay.modulo(day.weekday - configuration.firstWeekday, 7))
        return PageID(anchor: anchor, scope: scope)
    }
    public func pageCount(scope: CalendarScope) -> Int {
        let first = pageID(containing: configuration.minimumDate, scope: scope).anchor
        let last = pageID(containing: configuration.maximumDate, scope: scope).anchor
        return scope == .month ? (last.year - first.year) * 12 + last.month - first.month + 1
            : first.distance(to: last) / 7 + 1
    }
    public func page(at index: Int, scope: CalendarScope) throws -> PageID {
        guard (0..<pageCount(scope: scope)).contains(index) else { throw CalendarError.invalidPageIndex(index) }
        let first = pageID(containing: configuration.minimumDate, scope: scope).anchor
        let anchor = scope == .month ? try first.addingMonths(index) : CivilDay(ordinal: first.ordinal + index * 7)
        return PageID(anchor: anchor, scope: scope)
    }
    public func sectionIndex(for day: CivilDay, scope: CalendarScope) throws -> Int {
        let first = pageID(containing: configuration.minimumDate, scope: scope).anchor
        let target = pageID(containing: day, scope: scope).anchor
        let index = scope == .month ? (target.year - first.year) * 12 + target.month - first.month
            : first.distance(to: target) / 7
        guard (0..<pageCount(scope: scope)).contains(index) else { throw CalendarError.outOfBounds(day) }
        return index
    }
    public func isSelectable(_ day: CivilDay) -> Bool {
        day >= configuration.minimumDate && day <= configuration.maximumDate &&
            (try? day.date(in: configuration.timeZone)) != nil
    }
    public func grid(containing day: CivilDay, scope: CalendarScope) throws -> CalendarGrid {
        let id = pageID(containing: day, scope: scope)
        let leading = scope == .month ? CivilDay.modulo(id.anchor.weekday - configuration.firstWeekday, 7) : 0
        let rows = scope == .week ? 1 : (configuration.placeholders == .sixRows ? 6 : (leading + id.anchor.daysInMonth + 6) / 7)
        let start = id.anchor.ordinal - leading
        let cells = (0..<(rows * 7)).map { index in
            let date = CivilDay(ordinal: start + index)
            let position: MonthPosition = scope == .week || date.startOfMonth == id.anchor ? .current
                : (date < id.anchor ? .previous : .next)
            let hidden = scope == .month && position != .current && configuration.placeholders == .none
            return DayOccurrence(id: CellOccurrenceID(page: id, day: date), position: position,
                                 isHidden: hidden, isSelectable: !hidden && isSelectable(date))
        }
        return CalendarGrid(id: id, rowCount: rows, occurrences: cells)
    }
    public func index(of day: CivilDay, in grid: CalendarGrid) -> Int? {
        guard let first = grid.occurrences.first else { return nil }
        let index = first.day.distance(to: day)
        return grid.occurrences.indices.contains(index) ? index : nil
    }
}

public struct SelectionChange: Hashable, Sendable {
    public let added: [CivilDay]
    public let removed: [CivilDay]
    public let selection: [CivilDay]
    public let origin: SelectionOrigin
}

/// Value-based proposals let UIKit consult a delegate before committing a transaction.
public struct SelectionState: Hashable, Sendable {
    public private(set) var days: [CivilDay] = []
    private var membership: Set<CivilDay> = []
    public init() {}
    public var latest: CivilDay? { days.last }
    public func contains(_ day: CivilDay) -> Bool { membership.contains(day) }
    public func propose(_ proposed: [CivilDay], engine: CalendarEngine, origin: SelectionOrigin) throws -> SelectionChange? {
        var seen: Set<CivilDay> = []
        let ordered = proposed.filter { seen.insert($0).inserted }
        for day in ordered {
            guard day >= engine.configuration.minimumDate, day <= engine.configuration.maximumDate else {
                throw CalendarError.outOfBounds(day)
            }
            _ = try day.date(in: engine.configuration.timeZone)
        }
        switch engine.configuration.selectionMode {
        case .disabled where !ordered.isEmpty: throw CalendarError.selectionDisabled
        case .single where ordered.count > 1: throw CalendarError.multipleSelectionNotAllowed
        default: break
        }
        return change(to: ordered, origin: origin)
    }
    public func pruningChange(for engine: CalendarEngine) -> SelectionChange? {
        var valid = days.filter(engine.isSelectable)
        switch engine.configuration.selectionMode {
        case .disabled: valid.removeAll()
        case .single: valid = Array(valid.suffix(1))
        case .multiple: break
        }
        return change(to: valid, origin: .configuration)
    }
    public mutating func commit(_ change: SelectionChange) {
        days = change.selection
        membership = Set(days)
    }
    private func change(to ordered: [CivilDay], origin: SelectionOrigin) -> SelectionChange? {
        guard ordered != days else { return nil }
        let proposed = Set(ordered)
        return SelectionChange(added: ordered.filter { !membership.contains($0) },
                               removed: days.filter { !proposed.contains($0) }, selection: ordered, origin: origin)
    }
}
