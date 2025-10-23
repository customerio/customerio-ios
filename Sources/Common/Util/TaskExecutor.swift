import Foundation

/// Executes async operations on class instances using a fire-and-forget pattern.
public protocol TaskExecutor: Sendable {
    /// Executes an async operation without blocking the caller.
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
public final class DefaultTaskExecutor: TaskExecutor {
    @discardableResult
    public func execute<Target: AnyObject, Result: Sendable>(
        on target: Target,
        _ operation: @Sendable @escaping (Target) async throws -> Result
    ) -> Task<Result, Error> {
        Task { try await operation(target) }
    }
}
