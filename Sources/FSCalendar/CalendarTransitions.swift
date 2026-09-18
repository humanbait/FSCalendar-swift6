#if canImport(UIKit)
import UIKit
import FSCalendarCore

@MainActor final class CalendarTransition {
    let sourceMode: CalendarDisplayMode
    let targetMode: CalendarDisplayMode
    let sourcePage: CivilDay
    let targetPage: CivilDay
    let renderMode: CalendarDisplayMode
    let renderPage: CivilDay
    let sourceHeight: CGFloat
    let targetHeight: CGFloat
    let renderGridHeight: CGFloat
    var progress: CGFloat = 0
    var focusedRow = 0
    var rowOffset: CGFloat = 0
    var changesScope: Bool { sourceMode.scope != targetMode.scope && !sourceMode.isContinuous && !targetMode.isContinuous }
    var animator: UIViewPropertyAnimator?
    var snapshot: UIView?
    init(sourceMode: CalendarDisplayMode, targetMode: CalendarDisplayMode, sourcePage: CivilDay,
         targetPage: CivilDay, renderMode: CalendarDisplayMode, renderPage: CivilDay,
         sourceHeight: CGFloat, targetHeight: CGFloat, renderGridHeight: CGFloat) {
        self.sourceMode = sourceMode; self.targetMode = targetMode
        self.sourcePage = sourcePage; self.targetPage = targetPage
        self.renderMode = renderMode; self.renderPage = renderPage
        self.sourceHeight = sourceHeight; self.targetHeight = targetHeight; self.renderGridHeight = renderGridHeight
    }
}

extension FSCalendar {
    public func setDisplayMode(_ target: CalendarDisplayMode, animated: Bool = true) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        cancelTransition()
        guard target != mode else { return }
        if !animated || reduceMotion {
            let anchor = transitionAnchor()
            mode = target
            if case .month(let axis) = target { lastMonthAxis = axis }
            let previousPage = page
            page = engine.pageID(containing: anchor, scope: target.scope).anchor
            rebuild(mode: mode); updateHeader(); notifyHeight(animated: false)
            setNeedsLayout(); layoutIfNeeded()
            delegate?.calendar(self, didChangeDisplayMode: mode)
            if page != previousPage { delegate?.calendarCurrentPageDidChange(self) }
            return
        }
        try prepareTransition(to: target)
        finishInteractiveTransition(commit: true, animated: true)
    }
    public func beginInteractiveTransition(to target: CalendarDisplayMode) throws {
        guard !isMutating else { throw CalendarError.reentrantMutation }
        cancelTransition()
        guard !mode.isContinuous, !target.isContinuous, mode.scope != target.scope else {
            throw CalendarError.unsupportedDisplayMode
        }
        try prepareTransition(to: target)
    }
    func prepareTransition(to target: CalendarDisplayMode) throws {
        layoutIfNeeded()
        let anchor = transitionAnchor()
        let targetPage = engine.pageID(containing: anchor, scope: target.scope).anchor
        let changesScope = mode.scope != target.scope && !mode.isContinuous && !target.isContinuous
        let renderedMode = changesScope ? (mode.scope == .month ? mode : target) : target
        let renderedPage = changesScope && mode.scope == .month ? page : targetPage
        let sourceHeight = height(for: mode, page: page), targetHeight = height(for: target, page: targetPage)
        let gridHeight = CGFloat(rowCount(for: renderedPage, scope: renderedMode.scope)) * effectiveRowHeight
        let context = CalendarTransition(sourceMode: mode, targetMode: target, sourcePage: page,
                                         targetPage: targetPage, renderMode: renderedMode, renderPage: renderedPage,
                                         sourceHeight: sourceHeight, targetHeight: targetHeight, renderGridHeight: gridHeight)
        if !changesScope { context.snapshot = clipView.snapshotView(afterScreenUpdates: false) }
        transition = context; transitionPhase = .interactive
        rebuild(mode: renderedMode)
        collectionView.isScrollEnabled = false
        setNeedsLayout(); layoutIfNeeded()
        if let snapshot = context.snapshot { snapshot.frame = clipView.bounds; clipView.addSubview(snapshot) }
        let row: Int
        if let grid = try? engine.grid(containing: renderedPage, scope: .month), let index = engine.index(of: anchor, in: grid) {
            row = index / 7
        } else { row = 0 }
        context.focusedRow = row
        context.rowOffset = CGFloat(row) * effectiveRowHeight
        applyTransitionProgress(0, context: context, animated: false, notify: false)
    }
    func applyTransitionOpacity(to cell: UICollectionViewCell, at index: IndexPath) {
        guard let context = transition, context.changesScope else { cell.alpha = 1; return }
        let opacity = context.targetMode.scope == .week ? max(1 - context.progress * 1.1, 0) : context.progress
        cell.alpha = index.item / 7 == context.focusedRow ? 1 : opacity
    }
    private func applyTransitionProgress(_ progress: CGFloat, context: CalendarTransition, animated: Bool, notify: Bool = true) {
        context.progress = progress
        if context.changesScope {
            let ratio = context.targetMode.scope == .week ? progress : 1 - progress
            collectionView.transform = CGAffineTransform(translationX: 0, y: -context.rowOffset * ratio)
            for cell in collectionView.visibleCells {
                if let index = collectionView.indexPath(for: cell) { applyTransitionOpacity(to: cell, at: index) }
            }
        }
        context.snapshot?.alpha = 1 - progress
        if notify { notifyHeight(animated: animated) }
        setNeedsLayout(); layoutIfNeeded()
    }
    public func updateInteractiveTransition(progress: CGFloat) {
        guard let context = transition, transitionPhase == .interactive else { return }
        applyTransitionProgress(min(1, max(0, progress.isFinite ? progress : 0)), context: context, animated: false)
    }
    public func finishInteractiveTransition(commit: Bool, animated: Bool = true) {
        guard let context = transition, transitionPhase == .interactive else { return }
        transitionPhase = .settling
        guard animated, !reduceMotion else {
            completeTransition(context, commit: commit)
            return
        }
        // Capture height, focused-row movement and fading together, from the current drag position.
        let animator = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) { [weak self, weak context] in
            guard let self, let context, self.transition === context else { return }
            self.applyTransitionProgress(commit ? 1 : 0, context: context, animated: true)
        }
        context.animator = animator
        animator.addCompletion { [weak self, weak context] _ in
            guard let self, let context, self.transition === context else { return }
            self.completeTransition(context, commit: commit)
        }
        animator.startAnimation()
    }
    func updatePageHeight(from previousHeight: CGFloat, animated: Bool) {
        let shouldAnimate = animated && !reduceMotion &&
            !mode.isContinuous && previousHeight != preferredHeight
        let update = {
            self.notifyHeight(animated: shouldAnimate)
            self.setNeedsLayout(); self.layoutIfNeeded()
        }
        if shouldAnimate {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction], animations: update)
        } else {
            UIView.performWithoutAnimation(update)
        }
    }
    func completeTransition(_ context: CalendarTransition, commit: Bool) {
        guard transition === context else { return }
        let previousPage = page
        transition = nil; transitionPhase = .idle
        context.snapshot?.removeFromSuperview()
        collectionView.transform = .identity; collectionView.isScrollEnabled = true
        collectionView.visibleCells.forEach { $0.alpha = 1 }
        mode = commit ? context.targetMode : context.sourceMode
        page = commit ? context.targetPage : context.sourcePage
        if case .month(let axis) = mode { lastMonthAxis = axis }
        rebuild(mode: mode); updateHeader(); notifyHeight(animated: false)
        setNeedsLayout(); layoutIfNeeded()
        if commit {
            delegate?.calendar(self, didChangeDisplayMode: mode)
            if page != previousPage { delegate?.calendarCurrentPageDidChange(self) }
        }
    }
    func cancelTransition() {
        guard let context = transition else { return }
        context.animator?.stopAnimation(true)
        completeTransition(context, commit: false)
    }
    func transitionAnchor() -> CivilDay {
        let visible = Set(collectionView.visibleCells.compactMap { cell -> CivilDay? in
            guard let state = (cell as? FSCalendarCell)?.dayState,
                  state.occurrence.isSelectable, !state.occurrence.isHidden else { return nil }
            return state.occurrence.day
        })
        return CalendarTransitionPlan(engine: engine, currentPage: page, visibleDays: Array(visible),
            selectedDays: selectedDays, today: today, targetMode: mode).anchor
    }
    /// Forward a container's vertical pan here to coordinate a calendar above a scrolling list.
    public func handleScopeGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            let target: CalendarDisplayMode = mode == .week ? .month(lastMonthAxis) : .week
            try? beginInteractiveTransition(to: target)
        case .changed:
            guard let context = transition else { return }
            let distance = context.targetHeight - context.sourceHeight
            guard abs(distance) > 0.5 else { return }
            updateInteractiveTransition(progress: gesture.translation(in: self).y / distance)
        case .ended:
            guard let context = transition else { return }
            let velocity = gesture.velocity(in: self).y
            let direction: CGFloat = context.targetHeight > context.sourceHeight ? 1 : -1
            let commit = abs(velocity) > 150 ? velocity * direction > 0 : context.progress >= 0.5
            finishInteractiveTransition(commit: commit)
        case .cancelled, .failed:
            finishInteractiveTransition(commit: false)
        default: break
        }
    }
}
#endif
