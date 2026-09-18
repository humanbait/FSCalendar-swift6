import UIKit
import CalendarDemoSupport

@MainActor protocol UIKitCalendarDemoDriver: CalendarDemoDriver {
    var view: UIView { get }
    var initialHeight: CGFloat { get }
    func handleScopeGesture(_ gesture: UIPanGestureRecognizer)
}
