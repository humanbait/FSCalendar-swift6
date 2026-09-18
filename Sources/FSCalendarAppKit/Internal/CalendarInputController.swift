#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor final class CalendarInputController {
    weak var owner: FSCalendarView?
    var visited: Set<CivilDay> = []
    var removes = false
    var dragging = false
    private var scrollTask: Task<Void, Never>?
    private var scrollStart: NSPoint?
    private var scrollDistance: CGFloat = 0
    deinit { scrollTask?.cancel() }
    func cancelScroll() { scrollTask?.cancel(); scrollTask = nil; scrollStart = nil; scrollDistance = 0 }
    func accumulateScroll(_ delta: CGFloat, ended: Bool) {
        guard let owner, owner.transitionState == .idle, !owner.displayMode.isContinuous, delta.isFinite else { return }
        if scrollStart == nil { scrollStart = owner.scrollView.contentView.bounds.origin }
        scrollDistance -= delta
        var position = scrollStart ?? .zero
        let horizontal = owner.displayMode.isHorizontal, content = owner.calendarLayout.collectionViewContentSize
        if horizontal { position.x = max(0, min(content.width - owner.calendarLayout.viewport.width, position.x + scrollDistance)) }
        else { position.y = max(0, min(content.height - owner.calendarLayout.viewport.height, position.y + scrollDistance)) }
        owner.scrollView.contentView.scroll(to: position); owner.scrollView.reflectScrolledClipView(owner.scrollView.contentView)
        scrollTask?.cancel()
        if ended { settleScroll() }
        else {
            scrollTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
                self?.settleScroll()
            }
        }
    }
    func settleScroll() {
        guard let owner, let start = scrollStart else { return }
        let length = owner.displayMode.isHorizontal ? owner.calendarLayout.viewport.width : owner.calendarLayout.viewport.height
        let startSection = owner.calendarLayout.section(at: start)
        let direction = scrollDistance >= 0 ? 1 : -1
        let rtl = owner.displayMode.isHorizontal && owner.userInterfaceLayoutDirection == .rightToLeft
        let steps = abs(scrollDistance) >= min(60, length * 0.25) ? max(1, Int((abs(scrollDistance) / max(1, length)).rounded())) : 0
        let index = min(owner.calendarLayout.rows.count - 1, max(0, startSection + steps * direction * (rtl ? -1 : 1)))
        cancelScroll()
        if let day = try? owner.engine.page(at: index, scope: owner.displayMode.scope).anchor { try? owner.setCurrentPage(day) }
    }
    func begin(_ day: CivilDay) {
        guard let owner, owner.transitionState == .idle, owner.engine.isSelectable(day) else { return }
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
    override var acceptsFirstResponder: Bool { false }
    override func accessibilityChildren() -> [Any]? {
        let days = visibleItems().filter { !$0.view.isHidden && $0.view.frame.intersects(visibleRect) }
            .sorted { (($0 as? FSCalendarItem)?.dayState?.occurrence.day.description ?? "") < (($1 as? FSCalendarItem)?.dayState?.occurrence.day.description ?? "") }
            .map(\.view)
        let headers = visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader).filter { $0.frame.intersects(visibleRect) }
        return headers + days
    }
    override func setFrameSize(_ newSize: NSSize) {
        let content = collectionViewLayout?.collectionViewContentSize ?? .zero
        super.setFrameSize(NSSize(width: max(newSize.width, content.width), height: max(newSize.height, content.height)))
    }
}

@MainActor final class CalendarScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { false }
    weak var owner: FSCalendarView?
    override func scrollWheel(with event: NSEvent) {
        guard let owner else { super.scrollWheel(with: event); return }
        guard owner.transitionState == .idle else { return }
        if owner.displayMode.isContinuous { super.scrollWheel(with: event); return }
        let delta = owner.displayMode.isHorizontal && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        owner.input.accumulateScroll(delta, ended: event.momentumPhase == .ended || event.phase == .cancelled)
    }
}

@MainActor final class CalendarDayView: FlippedView {
    weak var owner: FSCalendarView?
    var day: CivilDay?
    override func accessibilityChildren() -> [Any]? { [] }
    override func isAccessibilityFocused() -> Bool { owner?.focusedDay == day && owner?.window?.firstResponder === owner }
    override func isAccessibilitySelected() -> Bool { day.map { owner?.selectedDays.contains($0) ?? false } ?? false }
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
        guard let owner, let day, owner.engine.isSelectable(day), owner.configuration.selectionMode != .disabled else { return false }
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
