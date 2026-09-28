import CioInternalCommon
import Foundation

/// The cold-wake restore path. Split out to stay under the file cap.
extension GeofenceSyncCoordinatorImpl {
    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        userId: String?
    ) -> GeofenceRegistration? {
        let syncStartedAt = GeofenceLog.monotonicNow()
        guard let userId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: .noIdentifiedUser)
            return nil
        }
        // No early return on an empty cache: the trigger stays armed for an empty nearby set, so
        // this re-arms it if the OS dropped our regions.
        guard let anchor else {
            logger.geofenceSyncSkipped(reason: .noLastSyncAnchor)
            return nil
        }
        // Stamped with the gate; see `acquireGateWithSequence`.
        guard let restoreSequence = acquireGateWithSequence() else {
            logger.geofenceSyncSkipped(reason: .restoreInProgress)
            return nil
        }
        defer {
            releaseGate()
            drainDeferredMovement(userChanged: false)
        }

        let effectiveConfig = config ?? .fallback
        let nearest = distanceFilter.nearest(monitorableRegions(cachedRegions), to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        let nearestIds = Set(nearest.map(\.id))
        logRanking(candidates: cachedRegions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let osRegistration = registerWithOsSync(
            businessRegions: nearest,
            movementTriggerLocation: anchor,
            // The full refresh radius, not a boundary-sized one: the stored anchor can be
            // arbitrarily far from the device here. The next movement pass re-arms against a fix.
            movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
            registerMovementTrigger: registerMovementTrigger
        )
        let registration = logRegistration(
            registeredIds: osRegistration.registeredIds,
            anchor: anchor,
            registerMovementTrigger: registerMovementTrigger,
            triggerRadius: effectiveConfig.localRefreshTriggerRadius
        )
        logSyncCompleted(registration, requested: (nearest.count, registerMovementTrigger), startedAt: syncStartedAt)
        // Retires older replays, using the sequence taken at entry: a fresh one would outrank a
        // movement that arrived while this was registering.
        if osRegistration.movementTriggerPlanted { noteMovementApplied(restoreSequence) }
        // No initial-enter: this restores the pre-kill set off a possibly-stale anchor; new fences
        // come from a refresh, which emits them. Only what the OS took, as in the refresh paths.
        return GeofenceRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
    }
}
