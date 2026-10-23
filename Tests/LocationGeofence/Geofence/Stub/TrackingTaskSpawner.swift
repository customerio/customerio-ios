@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Counts the work the SDK has started and not finished, so a test waits for it to go idle instead
/// of sleeping. Starts each task exactly as the live spawner does and watches it from a second task,
/// so tracking can't change where or when the work runs.
final class TrackingTaskSpawner: GeofenceTaskSpawning, @unchecked Sendable {
    struct IdleTimeout: Error, Equatable, CustomStringConvertible {
        let inFlight: Int
        let parked: Int

        var description: String {
            "Geofence replay idle deadline exceeded: inFlight=\(inFlight), parked=\(parked)"
        }
    }

    private struct Waiter {
        let continuation: CheckedContinuation<IdleTimeout?, Never>
        let deadline: DispatchWorkItem
    }

    private struct State {
        var inFlight = 0
        /// Work suspended at a boundary only the test releases.
        var parked = 0
        var idleWaiters: [UUID: Waiter] = [:]

        var isIdle: Bool { inFlight == parked }
    }

    private let state = Synchronized<State>(State())

    var inFlight: Int { state.wrappedValue.inFlight }

    @discardableResult
    func spawn<Success: Sendable>(
        @_inheritActorContext @_implicitSelfCapture _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        update { $0.inFlight += 1 }
        let task = Task(operation: operation)
        Task { [weak self] in
            _ = await task.value
            self?.update { $0.inFlight -= 1 }
        }
        return task
    }

    func workStarted() {
        update { $0.inFlight += 1 }
    }

    func workFinished() {
        update { $0.inFlight -= 1 }
    }

    /// Set by the boundary that parks the work, whenever its count changes.
    func setParked(_ count: Int) {
        update { $0.parked = count }
    }

    /// Uses a monotonic real-time deadline, independent of the replay's virtual clock.
    /// Returns a count snapshot on timeout, so the caller fails instead of hanging the CI job.
    func awaitIdle(timeout: TimeInterval = 10) async -> IdleTimeout? {
        await withCheckedContinuation { continuation in
            let id = UUID()
            let deadline = DispatchWorkItem { [weak self] in self?.expireWaiter(id) }
            let idleNow = state.mutating { state -> Bool in
                if state.isIdle { return true }
                state.idleWaiters[id] = Waiter(continuation: continuation, deadline: deadline)
                return false
            }
            if idleNow {
                continuation.resume(returning: nil)
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            }
        }
    }

    private func expireWaiter(_ id: UUID) {
        let expired = state.mutating { state -> (Waiter, IdleTimeout)? in
            guard let waiter = state.idleWaiters.removeValue(forKey: id) else { return nil }
            return (waiter, IdleTimeout(inFlight: state.inFlight, parked: state.parked))
        }
        if let (waiter, counts) = expired { waiter.continuation.resume(returning: counts) }
    }

    private func update(_ change: (inout State) -> Void) {
        let waiters = state.mutating { state -> [Waiter] in
            change(&state)
            guard state.isIdle else { return [] }
            defer { state.idleWaiters = [:] }
            return Array(state.idleWaiters.values)
        }
        waiters.forEach {
            $0.deadline.cancel()
            $0.continuation.resume(returning: nil)
        }
    }
}
