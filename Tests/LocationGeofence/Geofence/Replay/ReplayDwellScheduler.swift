@testable import CioLocationGeofence
import Foundation

/// Deadlines and retries share drive time. Cancellation resumes parked tasks rather than leaking them.
@MainActor
final class ReplayDwellScheduler {
    private struct Waiter {
        let deadline: TimeInterval
        let sequence: Int
        /// Whether the sleeping task is one the harness tracks, and so counts as parked.
        let tracked: Bool
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [UUID: Waiter] = [:] {
        didSet { onTrackedWaitersChanged?(waiters.values.filter(\.tracked).count) }
    }

    /// Whether the sleeping task is tracked work. Unset, none is.
    var isTrackedWork: () -> Bool = { false }
    /// Told how many tracked tasks sleep here whenever that changes.
    var onTrackedWaitersChanged: ((Int) -> Void)?
    /// Starts the hop a cancellation takes, so the harness waits for it. Nil starts a plain task.
    var taskSpawner: GeofenceTaskSpawning?
    private var sequence = 0
    private var stopped = false
    private(set) var now: TimeInterval = 0
    /// The OS froze the process. Drive time still moves; no deadline runs or is advertised.
    private(set) var isExecutionSuspended = false
    /// Nil while frozen, so a boundary gate cannot spin advancing toward a deadline that cannot run.
    var nextDeadline: TimeInterval? {
        isExecutionSuspended ? nil : waiters.values.map(\.deadline).min()
    }

    var pendingCount: Int { waiters.count }

    func sleep(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        guard nanoseconds > 0 else { return }
        let id = UUID()
        let deadline = now + TimeInterval(nanoseconds) / 1000000000
        let tracked = isTrackedWork()
        let taskSpawner = taskSpawner
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sequence += 1
                    waiters[id] = Waiter(deadline: deadline, sequence: sequence, tracked: tracked, continuation: continuation)
                }
            }
        } onCancel: {
            guard let taskSpawner else {
                Task { @MainActor [weak self] in self?.cancel(id) }
                return
            }
            taskSpawner.spawn { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    func advance(to moment: TimeInterval) {
        now = max(now, moment)
        releaseDue()
    }

    func suspendExecution() {
        isExecutionSuspended = true
    }

    /// Deadlines that passed while frozen run now and observe the resume time, never their old
    /// deadline. Resuming leaves a stopped process dead: `stop` cancelled its waiters for good.
    func resumeExecution() {
        isExecutionSuspended = false
        releaseDue()
    }

    private func releaseDue() {
        guard !isExecutionSuspended else { return }
        let due = waiters.filter { $0.value.deadline <= now }.sorted {
            ($0.value.deadline, $0.value.sequence) < ($1.value.deadline, $1.value.sequence)
        }
        for (id, waiter) in due {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    func cancelAll() {
        for id in Array(waiters.keys) {
            cancel(id)
        }
    }

    /// A dead process cannot park new work, including an immediate deadline from a late bootstrap.
    func stop() {
        stopped = true
        cancelAll()
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}
