import Foundation

public enum CalendarScrollAxis: Hashable, Sendable { case horizontal, vertical }
public enum CalendarDisplayMode: Hashable, Sendable {
    case month(CalendarScrollAxis)
    case week
    case continuousMonths
    public var scope: CalendarScope { self == .week ? .week : .month }
    public var isContinuous: Bool { self == .continuousMonths }
    public var isHorizontal: Bool { self == .week || self == .month(.horizontal) }
}
public enum CalendarTransitionState: Hashable, Sendable { case idle, interactive, settling }

public struct DayState: Hashable, Sendable {
    public init(occurrence: DayOccurrence, isSelected: Bool, isToday: Bool) {
        self.occurrence = occurrence; self.isSelected = isSelected; self.isToday = isToday
    }
    public let occurrence: DayOccurrence
    public let isSelected: Bool
    public let isToday: Bool
}

/// A synchronous, geometry-free decision shared by native renderers.
public struct CalendarTransitionPlan: Hashable, Sendable {
    public let anchor: CivilDay
    public let destinationPage: CivilDay
    public let targetMode: CalendarDisplayMode
    public init(engine: CalendarEngine, currentPage: CivilDay, visibleDays: [CivilDay],
                selectedDays: [CivilDay], today: CivilDay?, targetMode: CalendarDisplayMode) {
        let eligible = Set(visibleDays.filter(engine.isSelectable))
        let chosen = selectedDays.reversed().first(where: eligible.contains)
            ?? today.flatMap { eligible.contains($0) ? $0 : nil }
            ?? eligible.min()
            ?? min(engine.configuration.maximumDate, max(engine.configuration.minimumDate, currentPage))
        anchor = chosen
        destinationPage = engine.pageID(containing: chosen, scope: targetMode.scope).anchor
        self.targetMode = targetMode
    }
}
