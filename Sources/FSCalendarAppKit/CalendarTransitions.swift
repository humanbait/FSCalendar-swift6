#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import FSCalendarCore

@MainActor final class CalendarTransition {
    let sourceMode: CalendarDisplayMode
    let sourcePage: CivilDay
    let targetMode: CalendarDisplayMode
    let targetPage: CivilDay
    let renderMode: CalendarDisplayMode
    let renderPage: CivilDay
    let sourceHeight: CGFloat
    let targetHeight: CGFloat
    let renderGridHeight: CGFloat
    let sourceOffset: CGFloat
    let targetOffset: CGFloat
    var progress: CGFloat = 0
    var settlingCommit = true
    init(sourceMode: CalendarDisplayMode, sourcePage: CivilDay, plan: CalendarTransitionPlan,
         sourceHeight: CGFloat, targetHeight: CGFloat, renderMode: CalendarDisplayMode,
         renderPage: CivilDay, renderGridHeight: CGFloat, rowOffset: CGFloat) {
        self.sourceMode = sourceMode; self.sourcePage = sourcePage
        targetMode = plan.targetMode; targetPage = plan.destinationPage
        self.sourceHeight = sourceHeight; self.targetHeight = targetHeight
        self.renderMode = renderMode; self.renderPage = renderPage; self.renderGridHeight = renderGridHeight
        sourceOffset = sourceMode == .week ? rowOffset : 0
        targetOffset = plan.targetMode == .week ? rowOffset : 0
    }
}

extension FSCalendarView {
    public func setDisplayMode(_ target: CalendarDisplayMode, animated: Bool = true) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        cancelTransition()
        guard target != mode else { return }
        if !animated || reduceMotion {
            let plan = transitionPlan(to: target), previous = page
            mode = target; page = plan.destinationPage
            if case .month(let axis) = target { lastMonthAxis = axis }
            reconcileFocus(); rebuild(); needsLayout = true; layoutSubtreeIfNeeded()
            delegate?.calendar(self, didChangeDisplayMode: mode)
            if page != previous { delegate?.calendarCurrentPageDidChange(self) }
            return
        }
        prepareTransition(to: target)
        finishInteractiveTransition(commit: true)
    }
    public func beginInteractiveTransition(to target: CalendarDisplayMode) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        cancelTransition()
        guard !mode.isContinuous, !target.isContinuous, mode.scope != target.scope else { throw CalendarError.unsupportedDisplayMode }
        prepareTransition(to: target)
    }
    private func prepareTransition(to target: CalendarDisplayMode) {
        layoutSubtreeIfNeeded()
        let plan = transitionPlan(to: target)
        let changesScope = mode.scope != target.scope && !mode.isContinuous && !target.isContinuous
        let renderMode: CalendarDisplayMode = changesScope ? (mode.scope == .month ? mode : target) : target
        let renderPage = engine.pageID(containing: plan.anchor, scope: renderMode.scope).anchor
        let grid = try? engine.grid(containing: renderPage, scope: renderMode.scope)
        let row = grid.flatMap { engine.index(of: plan.anchor, in: $0) }.map { $0 / 7 } ?? 0
        let context = CalendarTransition(sourceMode: mode, sourcePage: page, plan: plan,
            sourceHeight: height(for: page, mode: mode), targetHeight: height(for: plan.destinationPage, mode: target),
            renderMode: renderMode, renderPage: renderPage, renderGridHeight: CGFloat(grid?.rowCount ?? 6) * metrics.rowHeight,
            rowOffset: changesScope ? CGFloat(row) * metrics.rowHeight : 0)
        transition = context; transitionPhase = .interactive
        rebuild(); needsLayout = true; layoutSubtreeIfNeeded()
    }
    public func updateInteractiveTransition(progress: CGFloat) {
        guard transitionPhase == .interactive else { return }
        updateTransitionProgress(progress)
    }
    private func updateTransitionProgress(_ progress: CGFloat) {
        guard let context = transition else { return }
        context.progress = min(1, max(0, progress.isFinite ? progress : 0))
        notifyHeight(animated: false); needsPagePosition = true; needsLayout = true; layoutSubtreeIfNeeded()
    }
    public func finishInteractiveTransition(commit: Bool, animated: Bool = true) {
        guard let context = transition else { return }
        animationDriver.cancel(); context.settlingCommit = commit; transitionPhase = .settling
        guard animated, !reduceMotion else { completeTransition(context, commit: commit); return }
        animationDriver.animate(from: context.progress, to: commit ? 1 : 0, update: { [weak self, weak context] progress in
            guard let self, let context, self.transition === context else { return }
            self.updateTransitionProgress(progress)
        }, completion: { [weak self, weak context] in
            guard let self, let context, self.transition === context else { return }
            self.completeTransition(context, commit: commit)
        })
    }
    func cancelTransition() {
        guard let context = transition else { return }
        animationDriver.cancel(); completeTransition(context, commit: false)
    }
    private func completeTransition(_ context: CalendarTransition, commit: Bool) {
        guard transition === context else { return }
        let previous = page
        transition = nil; transitionPhase = .idle
        mode = commit ? context.targetMode : context.sourceMode
        page = commit ? context.targetPage : context.sourcePage
        if case .month(let axis) = mode { lastMonthAxis = axis }
        reconcileFocus(); rebuild(); needsLayout = true; layoutSubtreeIfNeeded()
        if commit {
            delegate?.calendar(self, didChangeDisplayMode: mode)
            if page != previous { delegate?.calendarCurrentPageDidChange(self) }
        }
    }
    @objc func accessibilityDisplayChanged() {
        if reduceMotion, transitionPhase == .settling, let context = transition {
            animationDriver.cancel(); completeTransition(context, commit: context.settlingCommit)
        }
        updateHeader(); reload(dates: Set(collectionView.visibleItems().compactMap { ($0 as? FSCalendarItem)?.dayState?.occurrence.day }))
    }
    /// Forward a dedicated scope handle's pan. Ordinary list scrolling should keep its normal behavior.
    public func handleScopeGesture(_ gesture: NSPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            try? beginInteractiveTransition(to: mode == .week ? .month(lastMonthAxis) : .week)
        case .changed:
            guard let context = transition else { return }
            let distance = context.targetHeight - context.sourceHeight
            if abs(distance) > 0.5 { updateInteractiveTransition(progress: gesture.translation(in: self).y / distance) }
        case .ended:
            guard let context = transition else { return }
            let velocity = gesture.velocity(in: self).y, direction: CGFloat = context.targetHeight > context.sourceHeight ? 1 : -1
            finishInteractiveTransition(commit: abs(velocity) > 150 ? velocity * direction > 0 : context.progress >= 0.5)
        case .cancelled, .failed: finishInteractiveTransition(commit: false)
        default: break
        }
    }
}
#endif
