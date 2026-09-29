#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

/// Main-actor frame driver. Elapsed monotonic time (not tick count) determines progress.
/// Cancellation never runs a stale completion. No threaded NSAnimation callbacks cross isolation.
@MainActor final class CalendarAnimationDriver {
    private var task: Task<Void, Never>?
    private var playhead: CGFloat = 0
    private var towardEnd = true
    private var lastTick = ContinuousClock.now
    private let scopeDuration = 0.3
    deinit { task?.cancel() }
    func cancel() { task?.cancel(); task = nil }
    private func advancePlayhead() {
        let now = ContinuousClock.now
        let elapsed = lastTick.duration(to: now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        playhead = min(1, max(0, playhead + CGFloat(seconds / scopeDuration) * (towardEnd ? 1 : -1)))
        lastTick = now
    }
    func reverseScope(towardEnd: Bool) {
        advancePlayhead()
        self.towardEnd = towardEnd
    }
    func animateScope(update: @escaping @MainActor (CGFloat) -> Void,
                      completion: @escaping @MainActor (Bool) -> Void) {
        cancel(); playhead = 0; towardEnd = true; lastTick = ContinuousClock.now
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.advancePlayhead()
                let position = self.playhead
                update(position * position * (3 - 2 * position))
                guard !Task.isCancelled else { return }
                if (self.towardEnd && position >= 1) || (!self.towardEnd && position <= 0) {
                    self.task = nil; completion(self.towardEnd); return
                }
                do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
            }
        }
    }
    func animate(from: CGFloat, to: CGFloat, update: @escaping @MainActor (CGFloat) -> Void,
                 completion: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor [weak self] in
            let clock = ContinuousClock(), start = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = start.duration(to: clock.now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let linear = min(1, seconds / 0.28)
                let eased = linear * linear * (3 - 2 * linear)
                update(from + (to - from) * eased)
                if linear >= 1 { self?.task = nil; completion(); return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }
}
#endif
