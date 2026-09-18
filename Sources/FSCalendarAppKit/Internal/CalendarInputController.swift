#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor final class CalendarInputController {
    weak var owner: FSCalendarView?
    var visited: Set<CivilDay> = []
    var removes = false
    var dragging = false
    func begin(_ day: CivilDay) {
        guard let owner, owner.engine.isSelectable(day) else { return }
        owner.window?.makeFirstResponder(owner)
        try? owner.focus(day)
        visited = []; removes = owner.selectedDays.contains(day); dragging = true
        visit(day)
    }
    func visit(_ day: CivilDay) {
        guard let owner, owner.engine.isSelectable(day), visited.insert(day).inserted else { return }
        let proposed: [CivilDay]
        switch owner.configuration.selectionMode {
        case .disabled: return
        case .single: proposed = [day]
        case .multiple: proposed = removes ? owner.selectedDays.filter { $0 != day } : owner.selectedDays + [day]
        }
        try? owner.transact(proposed, origin: .user)
    }
    func drag(at point: NSPoint) {
        guard let owner, owner.swipeSelectionEnabled, dragging,
              let index = owner.collectionView.indexPathForItem(at: point),
              let grid = owner.controller.grid(index.section), grid.occurrences.indices.contains(index.item) else { return }
        visit(grid.occurrences[index.item].day)
    }
    func end() { dragging = false; visited.removeAll() }
    func activate(_ day: CivilDay) { begin(day); end() }
    func moveFocus(_ distance: Int) {
        guard let owner else { return }
        var next = owner.focusedDay ?? owner.firstEligibleDay()
        // Civil days skipped by the configured time zone cannot take focus.
        repeat {
            guard let candidate = try? next.addingDays(distance), candidate >= owner.configuration.minimumDate,
                  candidate <= owner.configuration.maximumDate else { return }
            next = candidate
        } while !owner.engine.isSelectable(next)
        try? owner.focus(next)
    }
}

@MainActor final class CalendarCollectionView: NSCollectionView {
    override func setFrameSize(_ newSize: NSSize) {
        let content = collectionViewLayout?.collectionViewContentSize ?? .zero
        super.setFrameSize(NSSize(width: max(newSize.width, content.width), height: max(newSize.height, content.height)))
    }
}

@MainActor final class CalendarScrollView: NSScrollView {
    // Paged scrolling is handled by the calendar, never by NSScrollView's document-origin fallback.
    override func scrollWheel(with event: NSEvent) {}
}

@MainActor final class CalendarDayView: FlippedView {
    weak var owner: FSCalendarView?
    var day: CivilDay?
    override func accessibilityFrame() -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
    override func mouseDown(with event: NSEvent) { if let day { owner?.input.begin(day) } }
    override func mouseDragged(with event: NSEvent) {
        guard let owner else { return }
        owner.input.drag(at: owner.collectionView.convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) { owner?.input.end() }
    override func accessibilityPerformPress() -> Bool {
        guard let owner, let day, owner.engine.isSelectable(day) else { return false }
        owner.input.activate(day); return true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // The entire day is one input and accessibility element, including its labels/image.
        guard super.hitTest(point) != nil else { return nil }
        return self
    }
}
#endif
