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
        let fetchStartedAt = dateUtil.now
        let fetchResult = await awaitApiFetch(latitude: latitude, longitude: longitude)
        let fetchElapsed = dateUtil.now.timeIntervalSince(fetchStartedAt)
        let response: GeofenceApiResponse
        switch fetchResult {
        case .success(let value):
            response = value
            // The count off the wire, before local filtering — the difference between what the
            // server offered and what survived ranking is the thing worth being able to see.
            logger.geofenceApiFetchResult(returnedCount: value.geofences.count, elapsed: fetchElapsed)
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
        let nearest = distanceFilter.nearest(regions, to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        logRanking(candidates: regions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
                registerMovementTrigger: registerMovementTrigger
            )
        }
        logRegistration(nearest: nearest, anchor: anchor, registerMovementTrigger: registerMovementTrigger, triggerRadius: effectiveConfig.localRefreshTriggerRadius)

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
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: config.maxBusinessGeofences, maxDistance: config.maxMonitoringDistance)
        let registerMovementTrigger = config.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        logRanking(candidates: cachedRegions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: config.localRefreshTriggerRadius,
                registerMovementTrigger: registerMovementTrigger
            )
        }
        logRegistration(nearest: nearest, anchor: anchor, registerMovementTrigger: registerMovementTrigger, triggerRadius: config.localRefreshTriggerRadius)
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

    // MARK: - Diagnostics

    /// The 19-of-N selection, which is otherwise invisible: a geofence that never registered
    /// because it ranked 20th looks exactly like one that registered and never fired.
    private func logRanking(candidates: [Geofence], nearest: [Geofence], nearestIds: Set<String>, anchor: LocationData) {
        logger.geofenceRankEvaluated(
            candidates: candidates.count,
            selected: nearest.map(\.id),
            evicted: candidates.map(\.id).filter { !nearestIds.contains($0) },
            edgeDistances: Dictionary(nearest.map { ($0.id, $0.edgeDistanceTo(anchor)) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// What the OS is actually monitoring now, by identifier, plus the movement bubble's geometry.
    private func logRegistration(nearest: [Geofence], anchor: LocationData, registerMovementTrigger: Bool, triggerRadius: Double) {
        logger.geofenceRegionsRegistered(
            identifiers: nearest.map(\.id),
            movementTrigger: registerMovementTrigger ? GeofenceConstants.movementTriggerIdentifier : nil
        )
        guard registerMovementTrigger else { return }
        logger.geofenceMovementTriggerRegistered(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            radius: triggerRadius
        )
    }
}
