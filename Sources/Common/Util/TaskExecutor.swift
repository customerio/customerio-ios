import Foundation

/// Executes async operations on class instances using a fire-and-forget pattern.
///
/// Provides a non-blocking way to execute async work without requiring the caller to `await`.
/// The abstraction is particularly useful for testing, where one can substitute synchronous
/// execution (via `TaskExecutorStub.blocking`) to make tests deterministic.
public protocol TaskExecutor: Sendable {
    /// Executes an async operation on a class instance without blocking the caller.
    ///
    /// - Parameters:
    ///   - target: The class instance the operation will access.
    ///   - operation: The async work to perform.
    /// - Returns: A `Task` handle that can be awaited or cancelled.
    @discardableResult
    func execute<Target: AnyObject, Result: Sendable>(
        on target: Target,
        _ operation: @Sendable @escaping (Target) async throws -> Result
    ) -> Task<Result, Error>
}

// sourcery: InjectRegisterShared = "TaskExecutor"
// sourcery: InjectSingleton
/// Default implementation that spawns detached tasks using Swift's `Task` API.
///
/// For testing, use `TaskExecutorStub.blocking` for synchronous execution or
/// `TaskExecutorStub.controllable()` for manual control over task completion.
public final class DefaultTaskExecutor: TaskExecutor {
    @discardableResult
    public func execute<Target: AnyObject, Result: Sendable>(
        on target: Target,
        _ operation: @Sendable @escaping (Target) async throws -> Result
    ) -> Task<Result, Error> {
        Task { try await operation(target) }
    }
}
