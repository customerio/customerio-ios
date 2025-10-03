import CioInternalCommon
import Foundation

/// Test stubs for ConcurrencySupport providing different execution behaviors.
///
/// Use `ConcurrencySupportStub.blocking` for simple synchronous execution,
/// or `ConcurrencySupportStub.controllable()` for fine-grained control over task completion.
public enum ConcurrencySupportStub {
    /// Creates a blocking stub that executes operations synchronously.
    /// Similar to runBlocking in Android - blocks the calling thread until the task completes.
    public static var blocking: ConcurrencySupport {
        BlockingStub()
    }

    /// Creates a controllable stub that allows manual control over task completion.
    /// Tasks are held until explicitly released via `completeAll()` or `completeNext()`.
    public static func controllable() -> ControllableStub {
        ControllableStub()
    }
}

// MARK: - Blocking Stub

/// Blocking implementation that executes tasks synchronously.
/// Times out after 5 seconds to prevent intermittent test hangs.
private final class BlockingStub: ConcurrencySupport {
    @discardableResult
    func execute<Caller: Actor, Result: Sendable>(
        on actor: Caller,
        _ operation: @Sendable @escaping (isolated Caller) async throws -> Result
    ) -> Task<Result, Error> {
        let semaphore = DispatchSemaphore(value: 0)

        let task = Task<Result, Error> {
            do {
                let result = try await operation(actor)
                semaphore.signal()
                return result
            } catch {
                semaphore.signal()
                throw error
            }
        }

        let timeout = DispatchTime.now() + .seconds(5)
        let result = semaphore.wait(timeout: timeout)

        if result == .timedOut {
            DIGraphShared.shared.logger.error("BlockingStub: Operation timed out after 5 seconds")
        }

        return task
    }
}

// MARK: - Controllable Stub

/// Controllable implementation that allows manual control over task completion.
public final class ControllableStub: ConcurrencySupport {
    private struct PendingTask {
        let continuation: CheckedContinuation<Void, Never>
    }

    private let pendingTasks = ThreadSafeBoxedValue<[PendingTask]>([])

    /// Completes all pending tasks.
    public func completeAll() {
        let tasks = pendingTasks.withValue { tasks in
            let copy = tasks
            tasks.removeAll()
            return copy
        }

        tasks.forEach { $0.continuation.resume() }
    }

    /// Completes the next pending task (FIFO order).
    public func completeNext() {
        let next = pendingTasks.withValue { tasks in
            tasks.isEmpty ? nil : tasks.removeFirst()
        }

        next?.continuation.resume()
    }

    /// Number of tasks currently waiting to be completed.
    public var pendingCount: Int {
        pendingTasks.withValue { $0.count }
    }

    @discardableResult
    public func execute<Caller: Actor, Result: Sendable>(
        on actor: Caller,
        _ operation: @Sendable @escaping (isolated Caller) async throws -> Result
    ) -> Task<Result, Error> {
        let task = Task<Result, Error> {
            // Wait for the test to release this task using continuations
            await withCheckedContinuation { continuation in
                pendingTasks.withValue { $0.append(PendingTask(continuation: continuation)) }
            }

            // Now execute the operation
            return try await operation(actor)
        }

        return task
    }
}
