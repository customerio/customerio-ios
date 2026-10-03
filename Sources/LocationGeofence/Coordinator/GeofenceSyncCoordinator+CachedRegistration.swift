import CioInternalCommon
import Foundation

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
        // No early return on an empty cache: the trigger must still be re-armed.
        guard let anchor else {
            logger.geofenceSyncSkipped(reason: .noLastSyncAnchor)
            return nil
        }
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
            // Full radius, not boundary-sized: the stored anchor can be far from the device.
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
        // The entry sequence: a fresh one would outrank a movement that arrived meanwhile.
        if osRegistration.movementTriggerPlanted { noteMovementApplied(restoreSequence) }
        // No initial-enter: the anchor may be stale; a refresh emits enters for new fences.
        return GeofenceRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
    }
}
