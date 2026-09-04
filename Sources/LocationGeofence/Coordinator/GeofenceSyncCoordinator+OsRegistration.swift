import CioInternalCommon
import Foundation

/// What the OS accepted for a registration sync: the identifiers actually monitored and the radius
/// cap the OS clamps every region to. Both feed the initial-enter decision.
struct GeofenceOsRegistration {
    let registeredIds: Set<String>
    let maxMonitoringRadius: Double
}

/// OS registration + fetch plumbing, split out to keep the coordinator's core flow readable.
/// Methods are `internal` (not `private`) only because they live in a separate file from their
/// callers; they remain coordinator implementation detail.
extension GeofenceSyncCoordinatorImpl {
    /// Bridges the completion-based nearby fetch to async.
    func awaitApiFetch(latitude: Double, longitude: Double) async -> Result<GeofenceApiResponse, GeofenceApiError> {
        await withCheckedContinuation { continuation in
            apiService.fetchNearbyGeofences(latitude: latitude, longitude: longitude) { continuation.resume(returning: $0) }
        }
    }

    /// Reconciles the OS-monitored set to the new business set + movement trigger, leaving regions
    /// that carry over registered untouched — see `setMonitoredRegions` for why re-adding them loses
    /// transitions. Returns the OS-accepted identifiers (a region the monitor dropped for blocked
    /// permission / invalid coordinates is absent) plus the radius cap, so `emitInitialEnters` won't
    /// fire an unbalanced synthetic enter or one for a device outside the actually-monitored
    /// (clamped) circle. `@MainActor`-isolated so a same-actor caller (e.g. `applyCachedRegistration`)
    /// can register without yielding — see the protocol doc for why that matters.
    @MainActor
    @discardableResult
    func registerWithOsSync(
        businessRegions: [Geofence],
        movementTriggerLocation: LocationData,
        movementTriggerRadius: Double,
        registerMovementTrigger: Bool
    ) -> GeofenceOsRegistration {
        var desired: [GeofenceRegionRequest] = []
        // Order the movement trigger FIRST so it isn't starved when business regions fill the
        // shared 20-region OS budget (e.g. a host app that also monitors regions): losing it freezes
        // the set, since exiting the trigger is what re-ranks toward now-closer geofences. Kept even
        // when the nearby set is empty (distance cap or an empty fetch) so the device keeps re-fetching
        // as it moves back toward geofences; skipped only when kill-switched (`maxBusinessGeofences == 0`).
        if registerMovementTrigger {
            desired.append(GeofenceRegionRequest(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                center: movementTriggerLocation,
                radius: movementTriggerRadius,
                transitionTypes: [.exit]
            ))
        }
        // A polygon whose covering circle exceeds the OS cap must be DROPPED, not clamped. Both
        // monitors clamp silently, and a clamped circle no longer contains the polygon — which
        // turns the covering-circle exit from geometric certainty into a false exit, and lets the
        // device enter through a part of the polygon no wake covers. Circles keep clamping: for
        // them the monitored circle IS the fence, so a smaller one only reports later.
        // Callers drop these before ranking so the slot is reused; this is the last-line guard for
        // anything that reached here anyway, and it logs so the skip is never silent.
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
                // A polygon's covering circle is machinery, not the customer's fence: it must report
                // BOTH edges so membership can advance. Registering it with the customer's types
                // would starve the resolver of the filtered edge — an enter-only polygon would fire
                // once and never again, an exit-only one never at all. The customer's filter is
                // applied to the polygon verdict instead.
                transitionTypes: region.vertices == nil ? region.transitionTypes : [.enter, .exit]
            )
        })
        let diff = monitor.setMonitoredRegions(desired)
        // Count against what the OS actually holds, not `desired`: a region dropped for blocked
        // permission or invalid coordinates is in neither, and would otherwise read as unchanged.
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
