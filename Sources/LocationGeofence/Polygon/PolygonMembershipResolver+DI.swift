import CioInternalCommon
import Foundation

// MARK: - DI

extension DIGraphShared {
    /// Hand-written because the resolver owns a `CLLocationManager` and is `@MainActor`.
    @MainActor
    var polygonMembershipResolver: PolygonMembershipResolver {
        let overridden: PolygonMembershipResolver? = getOverriddenInstance()
        return overridden ?? PolygonMembershipResolver.shared
    }
}

extension PolygonMembershipResolver {
    /// One instance, so one `CLLocationManager` serves every evaluation.
    @MainActor
    static let shared = PolygonMembershipResolver(
        storage: DIGraphShared.shared.geofenceStorage,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        logger: DIGraphShared.shared.logger,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore,
        dwellCoordinator: DIGraphShared.shared.geofenceDwellCoordinator
    )
}
