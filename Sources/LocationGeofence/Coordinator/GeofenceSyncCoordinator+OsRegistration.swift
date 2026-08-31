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
        registerMovementTrigger: Bool,
        tripwires: [String: PolygonTripwire] = [:]
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
        let maximumRadius = monitor.maximumMonitoringRadius
        let registrable = businessRegions.filter { region in
            guard region.vertices != nil, region.radius > maximumRadius else { return true }
            logger.geofencePolygonExceedsMonitoringLimit(
                identifier: region.id, radius: region.radius, limit: maximumRadius
            )
            return false
        }
        // Tripwires next, ahead of the business regions and for the same reason the movement
        // trigger is: a tripwire only exists while the device is inside that polygon's covering
        // circle, and losing it to a full budget would leave the annulus with no wake source at
        // all. Only for polygons still in this pass's set — one evicted from the set is no longer
        // evaluated, and its tripwire is pruned alongside its membership.
        let registeredIdsForTripwires = Set(registrable.map(\.id))
        desired.append(
            contentsOf: tripwires
                .filter { registeredIdsForTripwires.contains($0.key) }
                .sorted { $0.key < $1.key }
                .map { geofenceId, tripwire in
                    GeofenceRegionRequest(
                        identifier: GeofenceInternalIdentifier.tripwire(for: geofenceId),
                        center: tripwire.center,
                        radius: tripwire.radius,
                        transitionTypes: [.exit]
                    )
                }
        )
        desired.append(contentsOf: registrable.map { region in
            GeofenceRegionRequest(
                identifier: region.id,
                center: LocationData(latitude: region.latitude, longitude: region.longitude),
                radius: region.radius,
                transitionTypes: region.transitionTypes
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
