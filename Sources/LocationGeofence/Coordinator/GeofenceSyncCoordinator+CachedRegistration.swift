import CioInternalCommon
import Foundation

/// The cold-wake restore path, split out to keep the coordinator's core flow under the file cap.
/// `internal` (not `private`) only because it lives in a separate file from its callers; it
/// remains coordinator implementation detail.
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
        // No early return on an empty cache: an empty nearby response clears it while the movement
        // trigger stays armed, so this is what re-arms the trigger if the OS dropped our regions.
        // Need an anchor to distance-filter and to center the movement trigger. Skipping
        // when absent is safer than re-using an arbitrary location.
        guard let anchor else {
            logger.geofenceSyncSkipped(reason: .noLastSyncAnchor)
            return nil
        }
        // Stamped with the gate, not after registering: a movement arriving while this restore
        // is talking to the OS would otherwise hold the lower sequence and be retired by the
        // older restore coordinates.
        guard let restoreSequence = acquireGateWithSequence() else {
            logger.geofenceSyncSkipped(reason: .restoreInProgress)
            return nil
        }
        // Drains like every other gate holder: a movement that lost the gate to a cache restore
        // is still the only thing that re-centres the trigger.
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
            // The full refresh radius, NOT a boundary-sized one: this path has no live fix. While
            // monitoring is live the recorded centre stays within `localRefreshTriggerRadius` of
            // the device, but this path exists precisely because the OS dropped the regions and the
            // process died — nothing re-recorded it, so the device can be arbitrarily far away. A
            // boundary-sized circle there would be one the device already stands outside. The first
            // movement pass re-arms against a live fix.
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
        // Same reason as `refresh`: this planted the trigger, so a replay older than it must be
        // retired rather than allowed to move it back. The sequence is the one taken at entry, not
        // a fresh one — allocating here would rank this restore above a movement that arrived
        // while it was registering, and retire the newer coordinates.
        //
        // Keyed on what the OS holds, not on `registerMovementTrigger`: that flag is the intent to
        // register, and the OS still drops the trigger for blocked permission or invalid
        // coordinates. Retiring a replay off an intent that did not land strands the trigger.
        if osRegistration.movementTriggerPlanted { noteMovementApplied(restoreSequence) }
        // No initial-enter here: a cold-wake restore of the pre-kill set (not new registrations) off a
        // possibly-stale anchor. Genuinely-new fences come from a refresh fetch, which emits there.
        // Only what the OS took, for the same reason as the refresh paths: an oversized polygon is
        // deliberately unregistered, and recording it would have the resolver decide membership for
        // a fence with no wake behind it.
        return GeofenceRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
    }
}
