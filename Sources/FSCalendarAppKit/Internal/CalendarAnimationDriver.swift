#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

/// Main-actor frame driver. Elapsed monotonic time (not tick count) determines progress.
/// Cancellation never runs a stale completion. No threaded NSAnimation callbacks cross isolation.
@MainActor final class CalendarAnimationDriver {
    private var task: Task<Void, Never>?
    deinit { task?.cancel() }
    func cancel() { task?.cancel(); task = nil }
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
