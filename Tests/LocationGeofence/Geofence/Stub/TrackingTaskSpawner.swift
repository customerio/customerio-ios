@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Counts the work the SDK has started and not finished, so a test waits for it to go idle instead
/// of sleeping. Starts each task exactly as the live spawner does and watches it from a second task,
/// so tracking can't change where or when the work runs.
final class TrackingTaskSpawner: GeofenceTaskSpawning, @unchecked Sendable {
    private struct State {
        var inFlight = 0
        /// Work suspended at a boundary only the test releases.
        var parked = 0
        var idleWaiters: [CheckedContinuation<Void, Never>] = []

        var isIdle: Bool { inFlight == parked }
    }

    private let state = Synchronized<State>(State())

    var inFlight: Int { state.wrappedValue.inFlight }
    var idleWaiterCount: Int { state.wrappedValue.idleWaiters.count }

    /// The spawner that started the running task, inherited by any task it creates. Tells a boundary
    /// the work this spawner counts from a test's own tasks, which it must not count as parked.
    @TaskLocal static var current: ObjectIdentifier?

    /// Whether the running task, or the one that created it, was started here.
    var startedCurrentTask: Bool { Self.current == ObjectIdentifier(self) }

    @discardableResult
    func spawn<Success: Sendable>(
        @_inheritActorContext @_implicitSelfCapture _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        update { $0.inFlight += 1 }
        let task = Self.$current.withValue(ObjectIdentifier(self)) { Task(operation: operation) }
        countUntilFinished(task)
        return task
    }

    /// Counted as `spawn` counts. Unmarked as `current`: a detached task inherits no task-local.
    @discardableResult
    func spawnDetached<Success: Sendable>(
        _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        update { $0.inFlight += 1 }
        let task = Task.detached(operation: operation)
        countUntilFinished(task)
        return task
    }

    private func countUntilFinished<Success: Sendable>(_ task: Task<Success, Never>) {
        Task { [weak self] in
            _ = await task.value
            self?.update { $0.inFlight -= 1 }
        }
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

    /// Returns once everything started is finished or parked at a boundary the test controls, and
    /// still is when rechecked on the main actor. Parked work is published there, sometimes in the
    /// middle of a job that goes on to start the work it waits on: idle reads true until that job
    /// ends, so a waiter it woke only trusts a reading taken after it.
    @MainActor
    func awaitIdle() async {
        repeat {
            await waitForIdle()
        } while !state.wrappedValue.isIdle
    }

    private func waitForIdle() async {
        await withCheckedContinuation { continuation in
            let idleNow = state.mutating { state -> Bool in
                if state.isIdle { return true }
                state.idleWaiters.append(continuation)
                return false
            }
            if idleNow { continuation.resume() }
        }
    }

    private func update(_ change: (inout State) -> Void) {
        let waiters = state.mutating { state -> [CheckedContinuation<Void, Never>] in
            change(&state)
            guard state.isIdle else { return [] }
            defer { state.idleWaiters = [] }
            return state.idleWaiters
        }
        waiters.forEach { $0.resume() }
    }
}
