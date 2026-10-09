import Foundation

/// Deadlines and retries share drive time. Cancellation resumes parked tasks rather than leaking them.
@MainActor
final class ReplayDwellScheduler {
    private struct Waiter {
        let deadline: TimeInterval
        let sequence: Int
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [UUID: Waiter] = [:]
    private var sequence = 0
    private var stopped = false
    private(set) var now: TimeInterval = 0
    var nextDeadline: TimeInterval? { waiters.values.map(\.deadline).min() }
    var pendingCount: Int { waiters.count }

    func sleep(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        guard nanoseconds > 0 else { return }
        let id = UUID()
        let deadline = now + TimeInterval(nanoseconds) / 1000000000
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sequence += 1
                    waiters[id] = Waiter(deadline: deadline, sequence: sequence, continuation: continuation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    func advance(to moment: TimeInterval) {
        now = max(now, moment)
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
