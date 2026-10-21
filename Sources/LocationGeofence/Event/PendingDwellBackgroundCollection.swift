import Foundation

/// Decides whether an opt-in background location session should run while
/// polygon dwells are pending. The dwell coordinator stays the decision owner;
/// this type only tracks acquisition leases and their hard caps.
///
/// Each `Key` identifies one fence visit. Each value is an absolute deadline on
/// the injected monotonic clock, computed by the coordinator from visit entry.
/// While a key keeps being sent, its deadline can only move earlier, so a rearm
/// for the same visit never extends the cap and an expired lease stays expired.
@MainActor
final class PendingDwellBackgroundCollection<Key: Hashable> {
    typealias Nanoseconds = UInt64

    private let now: () -> Nanoseconds
    private let sleep: @Sendable (Nanoseconds) async throws -> Void
    private let start: () -> Void
    private let stop: () -> Void

    private var deadlines: [Key: Nanoseconds] = [:]
    private var permitted = false
    private var expiryTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private(set) var isRunning = false

    /// - Parameters:
    ///   - now: Monotonic clock that keeps counting across device sleep;
    ///     must be the clock the coordinator uses to compute lease deadlines.
    ///   - sleep: Waits the given nanoseconds of `now`'s timeline. No default: `Task.sleep(nanoseconds:)`
    ///     may count only awake time, which would keep the session past every cap while the device sleeps.
    init(
        now: @escaping () -> Nanoseconds,
        sleep: @escaping @Sendable (Nanoseconds) async throws -> Void,
        start: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        self.now = now
        self.sleep = sleep
        self.start = start
        self.stop = stop
    }

    // A released owner leaves no expiry wait parked until its deadline. Cancelling is safe from
    // the nonisolated deinit; the owner stops its own location session.
    deinit {
        expiryTask?.cancel()
    }

    /// Replaces the pending lease set; keys absent from `leases` are released.
    /// The session runs only while `enabled && eligible` and a lease is unexpired.
    func update(leases: [Key: Nanoseconds], enabled: Bool, eligible: Bool) {
        let previous = deadlines
        permitted = enabled && eligible
        deadlines = leases.reduce(into: [:]) { result, lease in
            result[lease.key] = min(lease.value, previous[lease.key] ?? lease.value)
        }
        reconcile()
    }

    /// Releases every lease and stops the session (opt-out, permission loss, identity reset).
    func endAll() {
        update(leases: [:], enabled: false, eligible: false)
    }

    private func reconcile() {
        expiryTask?.cancel()
        expiryTask = nil
        generation &+= 1
        let token = generation
        let current = now()
        let nextExpiry = permitted ? deadlines.values.filter { $0 > current }.min() : nil
        if (nextExpiry != nil) != isRunning {
            isRunning = nextExpiry != nil
            if isRunning { start() } else { stop() }
            // A re-entrant update from start/stop has already reconciled.
            guard generation == token else { return }
        }
        guard let expiry = nextExpiry else { return }
        let wait = sleep
        expiryTask = Task { [weak self] in
            // Measured as the wait begins, not when it was scheduled: a job that first runs after
            // the cap (the process suspended in between) stops at once instead of parking a full
            // delay. `self?` holds the collection for this call only, never across the wait.
            guard let delay = self?.remainingWait(until: expiry, token: token) else { return }
            if delay > 0 {
                do { try await wait(delay) } catch { return }
            }
            // A stale wake (including a sleep that ignores cancellation) cannot act on newer state.
            guard let self = self, self.generation == token else { return }
            self.reconcile()
        }
    }

    /// What the wait for `token` still needs before `expiry`, on the clock read now: zero once the
    /// cap has passed, nil once a newer reconcile has superseded that wait.
    private func remainingWait(until expiry: Nanoseconds, token: UInt64) -> Nanoseconds? {
        guard generation == token else { return nil }
        let current = now()
        return expiry > current ? expiry - current : 0
    }
}
