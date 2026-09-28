import CioInternalCommon
import Foundation

/// What the OS accepted for a registration sync: the identifiers actually monitored and the radius
/// cap it clamps every region to.
struct GeofenceOsRegistration {
    let registeredIds: Set<String>
    let maxMonitoringRadius: Double

    /// Whether the OS holds the movement trigger, which is what makes a pass a re-centre. Read off
    /// the monitor, not intent or success: the kill switch skips the trigger, and blocked permission
    /// or invalid coordinates drop it, while the pass still succeeds.
    var movementTriggerPlanted: Bool {
        registeredIds.contains(GeofenceConstants.movementTriggerIdentifier)
    }
}

/// OS registration and fetch plumbing. Internal only because it lives in a separate file from its
/// callers.
extension GeofenceSyncCoordinatorImpl {
    /// Bridges the completion-based nearby fetch to async.
    func awaitApiFetch(latitude: Double, longitude: Double) async -> Result<GeofenceApiResponse, GeofenceApiError> {
        await withCheckedContinuation { continuation in
            apiService.fetchNearbyGeofences(latitude: latitude, longitude: longitude) { continuation.resume(returning: $0) }
        }
    }

    /// Reconciles the OS-monitored set to the business set plus movement trigger (see
    /// `setMonitoredRegions`). Returns what the OS accepted and its radius cap, so
    /// `emitInitialEnters` skips regions the monitor dropped and judges against the clamped circle.
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
        // Movement trigger FIRST so it isn't starved when the shared 20-region budget fills (e.g. a
        // host app monitoring its own regions); losing it freezes the set. Kept even for an empty
        // nearby set so the device keeps re-fetching; skipped only under the kill switch.
        if registerMovementTrigger {
            desired.append(GeofenceRegionRequest(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                center: movementTriggerLocation,
                radius: movementTriggerRadius,
                transitionTypes: [.exit]
            ))
        }
        // A polygon whose covering circle exceeds the OS cap is DROPPED, not clamped: a clamped
        // circle no longer contains the polygon, so its exit is no longer proof of leaving and part
        // of the polygon has no wake. Circles still clamp. Callers already drop these before
        // ranking (`monitorableRegions`); this is the last-line guard.
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
                // A polygon's covering circle must report BOTH edges so membership can advance; the
                // customer's transition filter applies to the polygon verdict instead.
                transitionTypes: region.vertices == nil ? region.transitionTypes : [.enter, .exit]
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
        return GeofenceOsRegistration(
            registeredIds: registeredIds,
            maxMonitoringRadius: monitor.maximumMonitoringRadius
        )
    }
}
