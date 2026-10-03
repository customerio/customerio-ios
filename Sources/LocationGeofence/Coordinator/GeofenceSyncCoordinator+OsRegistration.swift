import CioInternalCommon
import Foundation

struct GeofenceOsRegistration {
    let registeredIds: Set<String>
    let maxMonitoringRadius: Double

    /// Read off the monitor, not intent: the trigger can be skipped or dropped while the pass succeeds.
    var movementTriggerPlanted: Bool {
        registeredIds.contains(GeofenceConstants.movementTriggerIdentifier)
    }
}

extension GeofenceSyncCoordinatorImpl {
    func awaitApiFetch(latitude: Double, longitude: Double) async -> Result<GeofenceApiResponse, GeofenceApiError> {
        await withCheckedContinuation { continuation in
            apiService.fetchNearbyGeofences(latitude: latitude, longitude: longitude) { continuation.resume(returning: $0) }
        }
    }

    /// `@MainActor` so `applyCachedRegistration` can register without yielding.
    @MainActor
    @discardableResult
    func registerWithOsSync(
        businessRegions: [Geofence],
        movementTriggerLocation: LocationData,
        movementTriggerRadius: Double,
        registerMovementTrigger: Bool
    ) -> GeofenceOsRegistration {
        var desired: [GeofenceRegionRequest] = []
        // Trigger FIRST so a full shared region budget can't starve it; losing it freezes the set.
        // Kept even for an empty nearby set.
        if registerMovementTrigger {
            desired.append(GeofenceRegionRequest(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                center: movementTriggerLocation,
                radius: movementTriggerRadius,
                transitionTypes: [.exit]
            ))
        }
        // Over-cap polygons are DROPPED, not clamped: a clamped circle no longer contains the polygon.
        // Last-line guard; `monitorableRegions` drops them before ranking.
        let maximumRadius = monitor.maximumMonitoringRadius
        let registrable = businessRegions.filter { region in
            guard region.vertices != nil, region.radius > maximumRadius else { return true }
            logger.geofencePolygonExceedsMonitoringLimit(
                identifier: region.id, radius: region.radius, limit: maximumRadius
            )
            return false
        }
        desired.append(contentsOf: registrable.map { region in
            GeofenceRegionRequest(
                identifier: region.id,
                center: LocationData(latitude: region.latitude, longitude: region.longitude),
                radius: region.radius,
                // Both edges so membership can advance; the customer's filter applies to the verdict.
                // A visit-tracking circle is widened too; `recordRegistrationIntent` records its extra
                // edges before this runs.
                transitionTypes: region.osTransitionTypes
            )
        })
        let diff = monitor.setMonitoredRegions(desired)
        // Against what the OS holds, not `desired`: a dropped region would otherwise read as unchanged.
        let registeredIds = monitor.monitoredRegionIdentifiers
        logger.geofenceRegistrationDiff(
            added: diff.added.count,
            removed: diff.removed.count,
            unchanged: registeredIds.count - diff.added.count
        )
        endDwellContinuity(unregistered: diff.removed)
        return GeofenceOsRegistration(
            registeredIds: registeredIds,
            maxMonitoringRadius: monitor.maximumMonitoringRadius
        )
    }

    /// A fence the SDK stops monitoring gets no EXIT, so nothing would ever close its visit. Left
    /// in place, the ENTER synthesized when a later re-rank registers it again would adopt that
    /// visit, and its dwell and EXIT would report a stay spanning all the time nothing watched the
    /// fence. Its continuity ends with the registration, as Android's registration incarnation does.
    /// Dated now, so the initial ENTER a re-register synthesizes later keeps the visit it opens.
    @MainActor
    private func endDwellContinuity(unregistered identifiers: Set<String>) {
        let geofenceIds = identifiers.subtracting([GeofenceConstants.movementTriggerIdentifier])
        guard let dwellCoordinator, !geofenceIds.isEmpty else { return }
        for geofenceId in geofenceIds {
            dwellCoordinator.interruptContinuity(geofenceId: geofenceId)
        }
    }
}
