import UIKit
import CalendarDemoSupport

@MainActor protocol UIKitCalendarDemoDriver: CalendarDemoDriver {
    var view: UIView { get }
    var initialHeight: CGFloat { get }
    func handleScopeGesture(_ gesture: UIPanGestureRecognizer)
}

@MainActor
enum DemoDriverFactory {
    static var implementations: [String] { ["legacy", "swift"] }
    static func make(_ implementation: String, scenario: DemoScenario) -> any UIKitCalendarDemoDriver {
        switch implementation {
        case "swift": SwiftCalendarDriver(scenario: scenario)
        default: LegacyCalendarDriver(scenario: scenario)
        }
    }
}
