import UIKit

enum DemoScenario: String, CaseIterable {
    case month, vertical, week, continuous, multiple, swipe, hidden, variable, sixRows
    case bounds, content, custom, range, scope, dynamicHeight, rtl, largeText, dark

    var title: String {
        switch self {
        case .month: "Month paging"
        case .vertical: "Vertical month paging"
        case .week: "Week paging"
        case .continuous: "Continuous months"
        case .multiple: "Multiple selection"
        case .swipe: "Swipe selection"
        case .hidden: "Hidden placeholders"
        case .variable: "Variable month rows"
        case .sixRows: "Six-row months"
        case .bounds: "Date bounds & Monday first"
        case .content: "Lunar subtitles & events"
        case .custom: "Custom cells"
        case .range: "Range picker"
        case .scope: "Interactive month / week"
        case .dynamicHeight: "Dynamic height"
        case .rtl: "Right-to-left layout"
        case .largeText: "Large text"
        case .dark: "Dark appearance"
        }
    }
}

enum DemoFixtures {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }
    static func date(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        precondition(parts.count == 3)
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }
    static func text(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static let initialDate = date("2024-02-14")
    static let minimumDate = date("2020-01-01")
    static let maximumDate = date("2030-12-31")
    static func lunarSubtitle(_ date: Date) -> String {
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = calendar.timeZone
        let days = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十", "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
        return days[lunar.component(.day, from: date) - 1]
    }
}

struct DemoState {
    let page: Date
    let scope: String
    let selection: [Date]
    let events: [String]
}

@MainActor
protocol CalendarDemoDriver: AnyObject {
    var view: UIView { get }
    var state: DemoState { get }
    var onChange: (() -> Void)? { get set }
    var onHeightChange: ((CGFloat, Bool) -> Void)? { get set }
    func reset()
    func navigate(_ offset: Int)
    func select(_ date: Date)
    func deselect(_ date: Date)
    func toggleScope()
    func handleScopeGesture(_ gesture: UIPanGestureRecognizer)
    func reloadContent()
}

@MainActor
enum DemoDriverFactory {
    static var implementations: [String] { ["legacy", "swift"] }
    static func make(_ implementation: String, scenario: DemoScenario) -> any CalendarDemoDriver {
        switch implementation {
        case "swift": SwiftCalendarDriver(scenario: scenario)
        default: LegacyCalendarDriver(scenario: scenario)
        }
    }
}
