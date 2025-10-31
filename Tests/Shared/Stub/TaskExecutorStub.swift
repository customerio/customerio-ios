import CioInternalCommon
import Foundation

/// Test stubs for TaskExecutor providing different execution behaviors.
///
/// Use `TaskExecutorStub.blocking` for simple synchronous execution,
/// or `TaskExecutorStub.controllable()` for fine-grained control over task completion.
public enum TaskExecutorStub {
    /// Creates a blocking stub that executes operations synchronously.
    /// Similar to runBlocking in Android - blocks the calling thread until the task completes.
    public static var blocking: TaskExecutor {
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
private final class BlockingStub: TaskExecutor {
    @discardableResult
    func execute<Target: AnyObject, Result: Sendable>(
        on target: Target,
        _ operation: @Sendable @escaping (Target) async throws -> Result
    ) -> Task<Result, Error> {
        let semaphore = DispatchSemaphore(value: 0)

        let task = Task<Result, Error> {
            do {
                let result = try await operation(target)
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
public final class ControllableStub: TaskExecutor {
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
    public func execute<Target: AnyObject, Result: Sendable>(
        on target: Target,
        _ operation: @Sendable @escaping (Target) async throws -> Result
    ) -> Task<Result, Error> {
        let task = Task<Result, Error> {
            // Wait for the test to release this task using continuations
            await withCheckedContinuation { continuation in
                pendingTasks.withValue { $0.append(PendingTask(continuation: continuation)) }
            }

            // Now execute the operation
            return try await operation(target)
        }

        return task
    }
}
