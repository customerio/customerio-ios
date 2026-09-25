import CioInternalCommon
import Foundation

// MARK: - DI

extension DIGraphShared {
    /// Hand-written + `@MainActor`-isolated for the same reason as `geofenceMonitor`: the resolver
    /// owns a `MovementFixResolver`, which owns a `CLLocationManager`. Override-check mirrors the
    /// generated accessors so tests can substitute via `di.override(value:forType:)`.
    @MainActor
    var polygonMembershipResolver: PolygonMembershipResolver {
        let overridden: PolygonMembershipResolver? = getOverriddenInstance()
        return overridden ?? PolygonMembershipResolver.shared
    }
}

extension PolygonMembershipResolver {
    /// Process-wide singleton so one `CLLocationManager` serves every evaluation; the resolver
    /// itself is stateless, all belief lives in `GeofenceStorage`.
    @MainActor
    static let shared = PolygonMembershipResolver(
        storage: DIGraphShared.shared.geofenceStorage,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        logger: DIGraphShared.shared.logger,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore
    )
}
