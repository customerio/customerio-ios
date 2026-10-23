import CioInternalCommon
import Foundation

/// Where the module starts fire-and-forget work. Production starts a plain `Task`; the replay harness
/// supplies one that can tell when everything it started has finished.
protocol GeofenceTaskSpawning: Sendable {
    /// Starts `operation` as a `Task { }` written at the call site would: same isolation, same order.
    @discardableResult
    func spawn<Success: Sendable>(
        @_inheritActorContext @_implicitSelfCapture _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never>

    /// Work that isn't a spawned task: an OS event from delivery until it is handled, and the event
    /// consumer until it has subscribed. Production has no use for either, so the live spawner
    /// ignores both.
    func workStarted()
    func workFinished()
}

struct LiveGeofenceTaskSpawner: GeofenceTaskSpawning {
    @discardableResult
    func spawn<Success: Sendable>(
        @_inheritActorContext @_implicitSelfCapture _ operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        Task(operation: operation)
    }

    func workStarted() {}
    func workFinished() {}
}

extension DIGraphShared {
    var geofenceTaskSpawner: GeofenceTaskSpawning {
        // Annotated: inferred from `??`, the lookup would be for `LiveGeofenceTaskSpawner` and miss.
        let overridden: GeofenceTaskSpawning? = getOverriddenInstance()
        return overridden ?? LiveGeofenceTaskSpawner()
    }
}
