import Foundation
import FSCalendarCore

/// Development-only contract. This module is not a dependency of any calendar product.
@MainActor public protocol RendererSelectionContract: AnyObject {
    var selectedDays: [CivilDay] { get }
    func apply(configuration: CalendarConfiguration) throws
    func select(_ day: CivilDay) throws
    func clearSelection() throws
    func setSelection(_ days: [CivilDay]) throws
    func reloadData()
    func navigate(_ offset: Int, animated: Bool) throws
    func setCurrentPage(_ day: CivilDay, animated: Bool) throws
}
public struct ContractFailure: Error, CustomStringConvertible {
    public let description: String
}
@MainActor public enum SharedRendererAssertions {
    public static func verifySelection(_ view: any RendererSelectionContract,
                                       changes: () -> [SelectionChange], allow: (Bool) -> Void) throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw ContractFailure(description: message) }
        }
        let a = try CivilDay(year: 2024, month: 2, day: 12), b = try a.addingDays(2)
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!))
        try view.setCurrentPage(a, animated: false)
        try view.select(a); try view.select(a); try view.select(b)
        try require(changes().count == 2, "Selection must emit once per change; no-op must be silent")
        try require(changes().last?.added == [b] && changes().last?.removed == [a], "Single selection must replace atomically")
        try require(view.selectedDays == [b], "Committed selection must match callback")
        allow(false)
        do { try view.select(a); throw ContractFailure(description: "Veto was ignored") }
        catch CalendarError.selectionVetoed {}
        try require(view.selectedDays == [b] && changes().count == 2, "Veto must preserve state and callback count")
        allow(true)
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!, selectionMode: .multiple))
        try view.select(a)
        try require(view.selectedDays == [b, a], "Multiple selection must preserve insertion order")
        view.reloadData(); try view.navigate(1, animated: false); try view.navigate(-1, animated: false)
        try require(view.selectedDays == [b, a], "Reload and navigation must preserve selection")
        allow(false)
        try view.apply(configuration: CalendarConfiguration(timeZone: TimeZone(secondsFromGMT: 0)!))
        try require(view.selectedDays == [a], "Switching to single must retain latest selection")
        try require(changes().last?.origin == .configuration, "Pruning must be one mandatory configuration transaction")
        allow(true)
        try view.clearSelection()
    }
}
