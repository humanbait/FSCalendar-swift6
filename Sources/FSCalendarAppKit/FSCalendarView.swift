#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

/// Native AppKit calendar. Rendering and input are added in the next milestones.
@MainActor public final class FSCalendarView: NSView {
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
#endif
