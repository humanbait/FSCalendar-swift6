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
    var isContinuousScope: Bool { sourceMode.scope != targetMode.scope && renderMode.isContinuous }
    var focusedRow = 0
    var continuousOffset = NSPoint.zero
    var rowOffset: CGFloat = 0
    var monthProgress: CGFloat { targetMode.isContinuous ? progress : 1 - progress }
    var titleFades: [(day: CivilDay, label: NSTextField, outgoing: NSView)] = []
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
        if animated, !reduceMotion, let context = transition, context.isContinuousScope,
           transitionPhase == .settling, target == context.sourceMode || target == context.targetMode {
            let commit = target == context.targetMode
            guard commit != context.settlingCommit else { return }
            context.settlingCommit = commit
            animationDriver.reverseScope(towardEnd: commit)
            return
        }
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
    func prepareTransition(to target: CalendarDisplayMode) {
        layoutSubtreeIfNeeded()
        let plan = transitionPlan(to: target)
        let changesScope = mode.scope != target.scope
        let renderMode: CalendarDisplayMode = changesScope ? (mode.scope == .month ? mode : target) : target
        let renderPage = engine.pageID(containing: plan.anchor, scope: renderMode.scope).anchor
        let grid = try? renderMode.isContinuous
            ? engine.continuousMonthGrid(containing: renderPage)
            : engine.grid(containing: renderPage, scope: renderMode.scope)
        let row = grid.flatMap { engine.index(of: plan.anchor, in: $0) }.map { $0 / 7 } ?? 0
        let continuousScope = changesScope && renderMode.isContinuous
        let sourceHeight = continuousScope && bounds.height > 0 ? bounds.height : height(for: page, mode: mode)
        let targetHeight = continuousScope && target.isContinuous
            ? (continuousViewportHeight ?? height(for: plan.destinationPage, mode: target))
            : height(for: plan.destinationPage, mode: target)
        var titles: [CivilDay: (String, NSView)] = [:]
        if continuousScope {
            for case let item as FSCalendarItem in collectionView.visibleItems() {
                guard let day = item.dayState?.occurrence.day, day.day == 1,
                      let bitmap = item.titleLabel.bitmapImageRepForCachingDisplay(in: item.titleLabel.bounds) else { continue }
                item.titleLabel.cacheDisplay(in: item.titleLabel.bounds, to: bitmap)
                let image = NSImage(size: item.titleLabel.bounds.size); image.addRepresentation(bitmap)
                titles[day] = (item.titleLabel.stringValue, NSImageView(image: image))
            }
        }
        let context = CalendarTransition(sourceMode: mode, sourcePage: page, plan: plan,
            sourceHeight: sourceHeight, targetHeight: targetHeight,
            renderMode: renderMode, renderPage: renderPage,
            renderGridHeight: continuousScope ? max(sourceHeight, targetHeight) - metrics.weekdayHeight : CGFloat(grid?.rowCount ?? 6) * metrics.rowHeight,
            rowOffset: changesScope ? CGFloat(row) * metrics.rowHeight : 0)
        if continuousScope {
            let sections = engine.continuousMonthSections()
            if let section = try? engine.sectionIndex(for: plan.anchor, scope: .month),
               let grid = try? engine.continuousMonthGrid(containing: plan.anchor), let item = engine.index(of: plan.anchor, in: grid),
               let renderSection = try? engine.sectionIndex(for: renderPage, scope: .month) {
                context.focusedRow = (sections[section].startSlot + item) / 7
                context.continuousOffset = mode.isContinuous ? scrollView.contentView.bounds.origin
                    : NSPoint(x: 0, y: CGFloat(sections[renderSection].firstRow) * metrics.rowHeight)
                context.rowOffset = CGFloat(context.focusedRow) * metrics.rowHeight - context.continuousOffset.y
            }
        }
        input.cancelScroll()
        transition = context; transitionPhase = .interactive
        updateHeader()
        if !continuousScope || !mode.isContinuous { rebuild(notify: false) }
        updateTransitionProgress(0, notify: false)
        if continuousScope {
            for case let item as FSCalendarItem in collectionView.visibleItems() {
                guard let occurrence = item.dayState?.occurrence,
                      let (oldTitle, snapshot) = titles[occurrence.day] else { continue }
                configure(item, occurrence: occurrence); item.view.layoutSubtreeIfNeeded()
                guard oldTitle != item.titleLabel.stringValue else { continue }
                snapshot.frame = item.titleLabel.frame; snapshot.setAccessibilityElement(false)
                item.titleLabel.superview?.addSubview(snapshot)
                item.titleLabel.alphaValue = 0
                context.titleFades.append((occurrence.day, item.titleLabel, snapshot))
            }
        }
    }
    public func updateInteractiveTransition(progress: CGFloat) {
        guard transitionPhase == .interactive else { return }
        updateTransitionProgress(progress)
    }
    private func updateTransitionProgress(_ progress: CGFloat, notify: Bool = true) {
        guard let context = transition else { return }
        context.progress = min(1, max(0, progress.isFinite ? progress : 0))
        if context.isContinuousScope {
            calendarLayout.focusedContinuousRow = context.focusedRow
            calendarLayout.continuousMonthOpacity = context.monthProgress
            calendarLayout.invalidateLayout()
            for fade in context.titleFades { fade.label.alphaValue = context.progress; fade.outgoing.alphaValue = 1 - context.progress }
        }
        if notify { notifyHeight(animated: false) }
        needsPagePosition = true; needsLayout = true; layoutSubtreeIfNeeded()
    }
    public func finishInteractiveTransition(commit: Bool, animated: Bool = true) {
        guard let context = transition else { return }
        animationDriver.cancel(); context.settlingCommit = commit; transitionPhase = .settling
        guard animated, !reduceMotion else { completeTransition(context, commit: commit); return }
        if context.isContinuousScope, commit, context.progress == 0 {
            animationDriver.animateScope(update: { [weak self, weak context] progress in
                guard let self, let context, self.transition === context else { return }
                self.updateTransitionProgress(progress)
            }, completion: { [weak self, weak context] commit in
                guard let self, let context, self.transition === context else { return }
                self.completeTransition(context, commit: commit)
            })
            return
        }
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
        if context.isContinuousScope, context.progress != (commit ? 1 : 0) { updateTransitionProgress(commit ? 1 : 0) }
        transition = nil; transitionPhase = .idle
        for fade in context.titleFades { fade.label.alphaValue = 1; fade.outgoing.removeFromSuperview() }
        calendarLayout.focusedContinuousRow = nil; calendarLayout.continuousMonthOpacity = 1
        titleLabel.alphaValue = 1
        mode = commit ? context.targetMode : context.sourceMode
        page = commit ? context.targetPage : context.sourcePage
        if case .month(let axis) = mode { lastMonthAxis = axis }
        reconcileFocus(); rebuild(notify: !context.isContinuousScope); needsLayout = true; layoutSubtreeIfNeeded()
        if context.isContinuousScope && mode.isContinuous && !commit {
            scrollView.contentView.scroll(to: context.continuousOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            needsPagePosition = false
        }
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
