import CioInternalCommon
import Foundation

/// The gated refresh tiers and their exit cleanup, split out to keep the coordinator's core flow
/// readable. Methods are `internal` (not `private`) only because they live in a separate file from
/// their callers; they remain coordinator implementation detail.
extension GeofenceSyncCoordinatorImpl {
    /// Fetch + filter + register + persist. Caller owns the dedup gate and user-id check;
    /// `expectedUserId` is the value captured before the API call so this helper can
    /// re-check that the identified user hasn't changed during the (potentially long) fetch.
    func performRemoteRefresh(
        expectedUserId: String,
        latitude: Double,
        longitude: Double,
        cachedConfig: GeofenceConfig?
    ) async -> Result<Void, GeofenceSyncError> {
        let fetchResult = await awaitApiFetch(latitude: latitude, longitude: longitude)
        let response: GeofenceApiResponse
        switch fetchResult {
        case .success(let value):
            response = value
        case .failure(let error):
            logger.geofenceSyncFetchFailed(error: error)
            return .failure(.fetchFailed(error))
        }

        // If the user signed out / changed during the API call, drop the result —
        // registering and persisting for a stale user would attribute geofences and
        // events to whoever signs in next.
        if contextStore.currentUserId != expectedUserId {
            logger.geofenceSyncSupersededByUserChange()
            return .success(())
        }

        let parsedConfig = response.toDomainConfig()
        let regions = response.toDomainRegions(onInvalidRegion: { logger.geofenceInvalidRegionDropped($0) })
        let effectiveConfig = parsedConfig ?? cachedConfig ?? .fallback
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let tripwires = await storage.getPolygonTripwires()
        let nearest = nearestBusinessRegions(regions, to: anchor, config: effectiveConfig, tripwires: tripwires)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
                registerMovementTrigger: registerMovementTrigger,
                tripwires: tripwires
            )
        }

        await storage.setCachedGeofences(regions)
        // Skip overwriting when the response did not ship a config — a previously cached
        // value must not be clobbered by a null parse from a partial-rollout backend.
        if let parsedConfig {
            await storage.setCachedConfig(parsedConfig)
        }
        await storage.recordSync(timestamp: dateUtil.now, location: anchor)
        await storage.recordRegistration(center: anchor, businessIds: nearestIds)
        emitInitialEnters(
            candidates: nearest,
            osRegistration: osRegistration,
            previouslyRegisteredIds: previouslyRegisteredIds,
            expectedUserId: expectedUserId,
            anchor: anchor
        )
        logger.geofenceSyncCompleted(registeredCount: nearest.count, movementTriggerRegistered: registerMovementTrigger)
        return .success(())
    }

    /// Re-rank cached regions for the new location and re-register with the OS. No API call and no
    /// `lastSync` write — the API-fetch anchor is what the re-fetch decision compares against, so
    /// leaving it intact preserves the next threshold. Records the registration anchor so the
    /// ranking-staleness reference follows the device after a local re-rank.
    func performLocalRefresh(
        expectedUserId: String,
        latitude: Double,
        longitude: Double,
        config: GeofenceConfig,
        cachedRegions: [Geofence]
    ) async -> Result<Void, GeofenceSyncError> {
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let tripwires = await storage.getPolygonTripwires()
        let nearest = nearestBusinessRegions(cachedRegions, to: anchor, config: config, tripwires: tripwires)
        let registerMovementTrigger = config.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: config.localRefreshTriggerRadius,
                registerMovementTrigger: registerMovementTrigger,
                tripwires: tripwires
            )
        }
        await storage.recordRegistration(center: anchor, businessIds: nearestIds)
        emitInitialEnters(
            candidates: nearest,
            osRegistration: osRegistration,
            previouslyRegisteredIds: previouslyRegisteredIds,
            expectedUserId: expectedUserId,
            anchor: anchor
        )
        logger.geofenceSyncCompleted(registeredCount: nearest.count, movementTriggerRegistered: registerMovementTrigger)
        return .success(())
    }

    /// A sign-out/switch can land anywhere inside a gated operation, and the `reset()` it triggers
    /// can't run while the gate is held — it returns `.alreadyInProgress` and is dropped. Runs at
    /// each gated method's single exit (gate still held) to undo the stale user's state, whichever
    /// path the body took. Initial-enter delivery re-checks the user per iteration on its own.
    /// Returns true when it cleaned, so the caller can trigger the current-user retry.
    func cleanupIfUserChanged(expectedUserId: String?) async -> Bool {
        guard let expectedUserId, contextStore.currentUserId != expectedUserId else { return false }
        await MainActor.run { monitor.stopMonitoringAll() }
        await storage.clearUserScopedState()
        logger.geofenceSyncSupersededByUserChange()
        return true
    }
}
