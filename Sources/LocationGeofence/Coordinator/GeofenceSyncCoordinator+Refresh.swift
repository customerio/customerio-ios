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
        anchor: LocationData,
        cachedConfig: GeofenceConfig?,
        anchorIsLiveFix: Bool
    ) async -> Result<Void, GeofenceSyncError> {
        let fetchResult = await awaitApiFetch(latitude: anchor.latitude, longitude: anchor.longitude)
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
        let monitorable = await MainActor.run { monitorableRegions(regions) }
        let nearest = distanceFilter.nearest(monitorable, to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let wakeRadius = wakeRadius(at: anchor, polygons: nearest, config: effectiveConfig, anchorIsLiveFix: anchorIsLiveFix)
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: wakeRadius,
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
        evaluatePolygonsAfterMovement(expectedUserId: expectedUserId)
        return .success(())
    }

    /// Re-rank cached regions for the new location and re-register with the OS. No API call and no
    /// `lastSync` write — the API-fetch anchor is what the re-fetch decision compares against, so
    /// leaving it intact preserves the next threshold. Records the registration anchor so the
    /// ranking-staleness reference follows the device after a local re-rank.
    func performLocalRefresh(
        expectedUserId: String,
        anchor: LocationData,
        config: GeofenceConfig,
        cachedRegions: [Geofence],
        anchorIsLiveFix: Bool
    ) async -> Result<Void, GeofenceSyncError> {
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
                movementTriggerRadius: wakeRadius(
                    at: anchor, polygons: nearest, config: config, anchorIsLiveFix: anchorIsLiveFix
                ),
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
        evaluatePolygonsAfterMovement(expectedUserId: expectedUserId)
        return .success(())
    }

    /// Re-arms the wake and re-evaluates membership, nothing more: the nearby set is unchanged, so
    /// ranking and cache writes would be waste. Must not `recordRegistration` — see
    /// `movedBeyondRerankRadius`.
    func performPolygonWakePass(
        expectedUserId: String,
        at location: LocationData,
        config: GeofenceConfig,
        anchorIsLiveFix: Bool
    ) async -> Result<Void, GeofenceSyncError> {
        let registeredIds = await storage.getRegisteredBusinessIds()
        let registered = await storage.getCachedGeofences().filter { registeredIds.contains($0.id) }
        let radius = wakeRadius(at: location, polygons: registered, config: config, anchorIsLiveFix: anchorIsLiveFix)
        logger.geofencePolygonWakePass(radius: radius, polygonCount: registered.count { $0.vertices != nil })
        _ = await MainActor.run {
            registerWithOsSync(
                businessRegions: registered,
                movementTriggerLocation: location,
                movementTriggerRadius: radius,
                registerMovementTrigger: config.maxBusinessGeofences > 0
            )
        }
        evaluatePolygonsAfterMovement(expectedUserId: expectedUserId)
        return .success(())
    }

    /// The trigger radius for a registration, sized to the nearest polygon boundary only when the
    /// anchor is a fix the caller holds.
    ///
    /// `anchorIsLiveFix` means "a fix no older than `movementFixMaxAge`", NOT "the device is here":
    /// a 30 s fix at speed is several hundred metres old, so a floor-sized trigger can still be
    /// planted around a point the device has left. On iOS 17+ that costs one spurious re-arm cycle
    /// and self-corrects; the classic path, where it would instead be a trigger that never fires,
    /// has to size the radius against the fix's age. Logged with the chosen radius so a drive can
    /// tell a spurious cycle from a real one — the fix's own age is on the line above it.
    /// A stored anchor can be a long way from the device —
    /// unbounded once the process has been dead — and a boundary-sized circle around it would be
    /// one the device already stands outside: a spurious cycle on iOS 17+, and on the classic path
    /// a trigger that never fires at all. The full refresh radius is the safe default there; the
    /// first movement pass re-arms against a live fix.
    private func wakeRadius(
        at anchor: LocationData,
        polygons: [Geofence],
        config: GeofenceConfig,
        anchorIsLiveFix: Bool
    ) -> Double {
        guard anchorIsLiveFix else {
            logger.geofenceWakeRadiusChosen(radius: config.localRefreshTriggerRadius, anchorIsLiveFix: false)
            return config.localRefreshTriggerRadius
        }
        let radius = PolygonWakeRadius.radius(at: anchor, registeredPolygons: polygons, config: config)
        logger.geofenceWakeRadiusChosen(radius: radius, anchorIsLiveFix: true)
        return radius
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
