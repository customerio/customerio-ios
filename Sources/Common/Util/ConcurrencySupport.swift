import Foundation

/// Abstraction for launching async work on actors.
///
/// Added to ease migration to Swift 6 concurrency. Instead of requiring
/// every caller to use `await`, operations can be wrapped here and updated
/// incrementally where needed.
public protocol ConcurrencySupport: Sendable {
    /// Launch an async operation on an actor.
    ///
    /// - Parameters:
    ///   - actor: Actor to run the operation on.
    ///   - operation: Closure isolated to the actor.
    /// - Returns: A `Task` handle that can be awaited or cancelled.
    ///
    /// - Note: The task is detached from any parent context; cancellation
    ///   must be managed explicitly.
    @discardableResult
    func execute<Caller: Actor, Result: Sendable>(
        on actor: Caller,
        _ operation: @Sendable @escaping (isolated Caller) async throws -> Result
    ) -> Task<Result, Error>
}

// sourcery: InjectRegisterShared = "ConcurrencySupport"
// sourcery: InjectSingleton
/// Default implementation for production, wrapping Swift concurrency `Task`.
///
/// Simply spawns a new task that runs the given actor-isolated operation.
public final class DefaultConcurrencySupport: ConcurrencySupport {
    @discardableResult
    public func execute<Caller: Actor, Result: Sendable>(
        on actor: Caller,
        _ operation: @Sendable @escaping (isolated Caller) async throws -> Result
    ) -> Task<Result, Error> {
        Task { try await operation(actor) }
    }
}
