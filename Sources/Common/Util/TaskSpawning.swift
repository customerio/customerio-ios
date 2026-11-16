import Foundation

/// Where SDK code starts fire-and-forget work. Production starts a plain `Task`; a test can supply a
/// spawner that knows when everything it started has finished, so it waits for that instead of
/// sleeping. SDK-internal: modules reach it through `@_spi(Internal) import CioInternalCommon`.
@_spi(Internal)
public protocol TaskSpawning: Sendable {
    /// Starts `operation` as a `Task { }` written at the call site would: same isolation, same
    /// priority and task-locals, same order.
    @discardableResult
    func spawn<Success: Sendable>(
        @_inheritActorContext @_implicitSelfCapture _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never>

    /// Starts `operation` as `Task.detached(priority:)` written at the call site would: no inherited
    /// isolation, priority or task-locals.
    @discardableResult
    func spawnDetached<Success: Sendable>(
        priority: TaskPriority?,
        _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never>
}

@_spi(Internal)
public struct LiveTaskSpawner: TaskSpawning {
    public init() {}

    @discardableResult
    public func spawn<Success: Sendable>(
        @_inheritActorContext @_implicitSelfCapture _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        Task(operation: operation)
    }

    @discardableResult
    public func spawnDetached<Success: Sendable>(
        priority: TaskPriority?,
        _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        Task.detached(priority: priority, operation: operation)
    }
}

public extension DIGraphShared {
    /// Hand-written: the live spawner unless a test overrides it. Named after the type so generated
    /// constructors resolve it.
    @_spi(Internal)
    var taskSpawning: TaskSpawning {
        // Annotated: inferred from `??`, the lookup would be for `LiveTaskSpawner` and miss.
        let overridden: TaskSpawning? = getOverriddenInstance()
        return overridden ?? LiveTaskSpawner()
    }
}
