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
        let regions: [Geofence]
        switch readableRegions(from: response) {
        case .success(let value): regions = value
        case .failure(let error): return .failure(error)
        }
        let effectiveConfig = parsedConfig ?? cachedConfig ?? .fallback
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let monitorable = await MainActor.run { monitorableRegions(regions) }
        let nearest = distanceFilter.nearest(monitorable, to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
                registerMovementTrigger: registerMovementTrigger
            )
        }

        await storage.setCachedGeofences(regions)
        // Skip overwriting when the response did not ship a config — a previously cached
        // value must not be clobbered by a null parse from a partial-rollout backend.
        if let parsedConfig {
            await storage.setCachedConfig(parsedConfig)
        }
        await storage.recordSync(timestamp: dateUtil.now, location: anchor)
        // Only what the OS accepted: an oversized polygon is deliberately not registered, and
        // recording it anyway would have the membership resolver evaluate a fence with no wake
        // behind it — delivering an enter that nothing can ever balance with an exit.
        await storage.recordRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
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
        let monitorable = await MainActor.run { monitorableRegions(cachedRegions) }
        let nearest = distanceFilter.nearest(monitorable, to: anchor, limit: config.maxBusinessGeofences, maxDistance: config.maxMonitoringDistance)
        let registerMovementTrigger = config.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: config.localRefreshTriggerRadius,
                registerMovementTrigger: registerMovementTrigger
            )
        }
        // Only what the OS accepted: an oversized polygon is deliberately not registered, and
        // recording it anyway would have the membership resolver evaluate a fence with no wake
        // behind it — delivering an enter that nothing can ever balance with an exit.
        await storage.recordRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
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

    /// Decodes the response's regions, or fails when the payload turns out to be unreadable rather
    /// than empty. A response whose regions we could not READ is a broken payload, not "this user
    /// has no geofences": reading it as the latter wipes the cache and deregisters everything. A
    /// workspace that has moved entirely to a shape this SDK does not support is the opposite case
    /// — the response read fine and nothing in it is monitorable, so failing forever would freeze
    /// stale fences behind a refresh that can never succeed. An actually empty list applies
    /// normally.
    private func readableRegions(from response: GeofenceApiResponse) -> Result<[Geofence], GeofenceSyncError> {
        var unreadableCount = 0
        let regions = response.toDomainRegions(onInvalidRegion: { id, reason in
            logger.geofenceInvalidRegionDropped(id, reason: reason)
            // A shape we understood and declined is not a payload we failed to read.
            if reason != .unknownShape { unreadableCount += 1 }
        })
        // Regions lost at JSON decode never reach `toDomainRegions` — it maps over what survived —
        // so they have to be counted from the arrival tally instead. A wrong-typed radius or
        // timestamp lands here, and it is unreadable in exactly the sense that matters.
        let decodeLosses = response.receivedRegionCount - response.geofences.count
        guard regions.isEmpty, unreadableCount + decodeLosses > 0 else { return .success(regions) }
        logger.geofenceAllRegionsDropped(count: response.receivedRegionCount)
        return .failure(.fetchFailed(.decoding))
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
