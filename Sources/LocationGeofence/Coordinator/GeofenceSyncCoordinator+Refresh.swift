import CioInternalCommon
import Foundation

/// The gated refresh tiers and their exit cleanup. Internal only because they live in a separate
/// file from their callers.
extension GeofenceSyncCoordinatorImpl {
    /// Fetch, filter, register, persist. The caller owns the gate; `expectedUserId` is captured
    /// before the fetch so the result can be dropped if the user changed during it.
    func performRemoteRefresh(
        expectedUserId: String,
        anchor: LocationData,
        cachedConfig: GeofenceConfig?,
        anchorIsLiveFix: Bool,
        heldFix: ResolvedFix? = nil
    ) async -> MovementPassOutcome {
        let syncStartedAt = GeofenceLog.monotonicNow()
        let response: GeofenceApiResponse
        switch await fetchForRefresh(anchor: anchor, startedAt: syncStartedAt) {
        case .success(let value): response = value
        case .failure(let error): return MovementPassOutcome(result: .failure(error), reCentred: false)
        }

        // Registering for a stale user would attribute geofences and events to whoever signs in next.
        if contextStore.currentUserId != expectedUserId {
            logger.geofenceSyncSupersededByUserChange()
            // Not a re-centre: nothing moved, so a queued movement must not be retired as overtaken.
            return MovementPassOutcome(result: .success(()), reCentred: false)
        }

        let parsedConfig = response.toDomainConfig()
        let regions: [Geofence]
        switch readableRegions(from: response) {
        case .success(let value): regions = value
        case .failure(let error): return MovementPassOutcome(result: .failure(error), reCentred: false)
        }
        let effectiveConfig = parsedConfig ?? cachedConfig ?? .fallback
        let monitorable = await MainActor.run { monitorableRegions(regions) }
        let nearest = distanceFilter.nearest(monitorable, to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let wakeRadius = wakeRadius(at: anchor, polygons: nearest, config: effectiveConfig, anchorIsLiveFix: anchorIsLiveFix)
        logRanking(candidates: regions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: wakeRadius,
                registerMovementTrigger: registerMovementTrigger
            )
        }
        let registration = logRegistration(registeredIds: osRegistration.registeredIds, anchor: anchor, registerMovementTrigger: registerMovementTrigger, triggerRadius: wakeRadius)

        await persistRemoteRefresh(
            regions: regions, parsedConfig: parsedConfig, anchor: anchor,
            registeredIds: nearestIds.intersection(osRegistration.registeredIds)
        )
        emitInitialEnters(
            candidates: nearest,
            osRegistration: osRegistration,
            previouslyRegisteredIds: previouslyRegisteredIds,
            expectedUserId: expectedUserId,
            anchor: anchor
        )
        logSyncCompleted(registration, requested: (nearest.count, registerMovementTrigger), startedAt: syncStartedAt)
        evaluatePolygonsAfterMovement(expectedUserId: expectedUserId, heldFix: heldFix)
        return MovementPassOutcome(result: .success(()), reCentred: osRegistration.movementTriggerPlanted)
    }

    private func fetchForRefresh(
        anchor: LocationData,
        startedAt: TimeInterval
    ) async -> Result<GeofenceApiResponse, GeofenceSyncError> {
        switch await awaitApiFetch(latitude: anchor.latitude, longitude: anchor.longitude) {
        case .success(let value):
            // Logged before local filtering, so what the server offered can be compared with what
            // survived ranking.
            logger.geofenceApiFetchResult(
                returnedCount: value.geofences.count,
                elapsed: GeofenceLog.monotonicNow() - startedAt,
                regions: value.geofences
            )
            return .success(value)
        case .failure(let error):
            logger.geofenceSyncFetchFailed(error: error)
            return .failure(.fetchFailed(error))
        }
    }

    func setOnConfigPersisted(_ handler: (@Sendable () -> Void)?) {
        onConfigPersisted.wrappedValue = handler
    }

    private func persistRemoteRefresh(
        regions: [Geofence],
        parsedConfig: GeofenceConfig?,
        anchor: LocationData,
        registeredIds: Set<String>
    ) async {
        await storage.setCachedGeofences(regions)
        // A response without a config must not clobber the cached one.
        if let parsedConfig {
            await storage.setCachedConfig(parsedConfig)
            onConfigPersisted.wrappedValue?()
        }
        await storage.recordSync(timestamp: dateUtil.now, location: anchor)
        // Only what the OS accepted: recording an unregistered (e.g. oversized) polygon would have
        // the resolver deliver an enter that no exit can ever balance.
        await storage.recordRegistration(center: anchor, businessIds: registeredIds)
    }

    /// Re-ranks cached regions and re-registers with the OS. No API call and no `lastSync` write:
    /// the fetch anchor is what the refetch decision measures from. Records the registration
    /// centre so the re-rank reference follows the device.
    func performLocalRefresh(
        expectedUserId: String,
        anchor: LocationData,
        config: GeofenceConfig,
        cachedRegions: [Geofence],
        anchorIsLiveFix: Bool,
        heldFix: ResolvedFix? = nil
    ) async -> MovementPassOutcome {
        let syncStartedAt = GeofenceLog.monotonicNow()
        let monitorable = await MainActor.run { monitorableRegions(cachedRegions) }
        let nearest = distanceFilter.nearest(monitorable, to: anchor, limit: config.maxBusinessGeofences, maxDistance: config.maxMonitoringDistance)
        let registerMovementTrigger = config.maxBusinessGeofences > 0
        // Read before `recordRegistration` overwrites it — the diff decides which registrations are new.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        logRanking(candidates: cachedRegions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let wakeRadius = wakeRadius(at: anchor, polygons: nearest, config: config, anchorIsLiveFix: anchorIsLiveFix)
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: wakeRadius,
                registerMovementTrigger: registerMovementTrigger
            )
        }
        let registration = logRegistration(registeredIds: osRegistration.registeredIds, anchor: anchor, registerMovementTrigger: registerMovementTrigger, triggerRadius: wakeRadius)
        // Only what the OS accepted, as in `persistRemoteRefresh`.
        await storage.recordRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
        emitInitialEnters(
            candidates: nearest,
            osRegistration: osRegistration,
            previouslyRegisteredIds: previouslyRegisteredIds,
            expectedUserId: expectedUserId,
            anchor: anchor
        )
        logSyncCompleted(registration, requested: (nearest.count, registerMovementTrigger), startedAt: syncStartedAt)
        evaluatePolygonsAfterMovement(expectedUserId: expectedUserId, heldFix: heldFix)
        return MovementPassOutcome(result: .success(()), reCentred: osRegistration.movementTriggerPlanted)
    }

    /// Re-arms the trigger and re-evaluates membership; the nearby set is unchanged, so no ranking or
    /// cache writes. Must not `recordRegistration`: see `movedBeyondRerankRadius`.
    func performPolygonWakePass(
        expectedUserId: String,
        at location: LocationData,
        config: GeofenceConfig,
        anchorIsLiveFix: Bool,
        heldFix: ResolvedFix? = nil
    ) async -> MovementPassOutcome {
        let registeredIds = await storage.getRegisteredBusinessIds()
        let registered = await storage.getCachedGeofences().filter { registeredIds.contains($0.id) }
        let radius = wakeRadius(at: location, polygons: registered, config: config, anchorIsLiveFix: anchorIsLiveFix)
        logger.geofencePolygonWakePass(radius: radius, polygonCount: registered.count { $0.vertices != nil })
        let osRegistration = await MainActor.run {
            registerWithOsSync(
                businessRegions: registered,
                movementTriggerLocation: location,
                movementTriggerRadius: radius,
                registerMovementTrigger: config.maxBusinessGeofences > 0
            )
        }
        evaluatePolygonsAfterMovement(expectedUserId: expectedUserId, heldFix: heldFix)
        return MovementPassOutcome(result: .success(()), reCentred: osRegistration.movementTriggerPlanted)
    }

    /// The trigger radius, sized to the nearest polygon boundary only when the anchor is a live fix.
    /// A stored anchor can be arbitrarily far from the device, so a boundary-sized circle around it
    /// may already exclude the device; the full refresh radius is used and the next movement pass
    /// re-arms against a fix.
    ///
    /// Known gap: "live" means no older than `movementFixMaxAge`, so at speed a tight trigger can
    /// still be planted around a point the device has left. On the CLMonitor path (iOS 18+) that
    /// costs one spurious re-arm; on the classic path the trigger may never fire.
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

    /// Decodes the response's regions, failing when none survive and any was unreadable. Treating
    /// a broken payload as "no geofences" would wipe the cache and deregister everything. Regions
    /// dropped only for a shape this SDK doesn't support, or a genuinely empty list, apply normally,
    /// so a workspace that moved to an unsupported shape doesn't freeze stale fences forever.
    private func readableRegions(from response: GeofenceApiResponse) -> Result<[Geofence], GeofenceSyncError> {
        var unreadableCount = 0
        let regions = response.toDomainRegions(onInvalidRegion: { id, reason in
            logger.geofenceInvalidRegionDropped(id, reason: reason)
            // A shape the server named but this version doesn't implement is unsupported, not
            // unreadable. `undescribedShape` (polygon fields, no discriminator) is malformed and counts.
            if reason != .unknownShape { unreadableCount += 1 }
        })
        // Regions lost at JSON decode (e.g. a wrong-typed radius) never reach `toDomainRegions`,
        // so count them from the arrival tally.
        let decodeLosses = response.receivedRegionCount - response.geofences.count
        guard regions.isEmpty, unreadableCount + decodeLosses > 0 else { return .success(regions) }
        logger.geofenceAllRegionsDropped(count: response.receivedRegionCount)
        return .failure(.fetchFailed(.decoding))
    }

    /// A sign-out/switch can land inside a gated operation, and the `reset()` it triggers is dropped
    /// while the gate is held. Runs at each gated method's single exit, gate still held, to undo
    /// the stale user's state. Returns true when it cleaned, so the caller can retry for the
    /// current user.
    func cleanupIfUserChanged(expectedUserId: String?) async -> Bool {
        guard let expectedUserId, contextStore.currentUserId != expectedUserId else { return false }
        // Clear before the OS stop — same ordering rule as `reset`, same reason.
        await storage.clearUserScopedState()
        await MainActor.run { monitor.stopMonitoringAll() }
        logger.geofenceSyncSupersededByUserChange()
        return true
    }

    // MARK: - Diagnostics

    /// Makes the top-N selection visible: a geofence that ranked out looks exactly like one that
    /// registered and never fired.
    func logSyncCompleted(
        _ registration: (accepted: [String], movementTrigger: Bool),
        requested: (count: Int, movementTrigger: Bool),
        startedAt: TimeInterval
    ) {
        logger.geofenceSyncCompleted(
            requestedCount: requested.count,
            movementTriggerRequested: requested.movementTrigger,
            acceptedCount: registration.accepted.count,
            movementTriggerAccepted: registration.movementTrigger,
            elapsed: GeofenceLog.monotonicNow() - startedAt
        )
    }

    func logRanking(candidates: [Geofence], nearest: [Geofence], nearestIds: Set<String>, anchor: LocationData) {
        logger.geofenceRankEvaluated(
            candidates: candidates.count,
            selectedCount: nearest.count,
            selected: nearest.map(\.id),
            evicted: candidates.map(\.id).filter { !nearestIds.contains($0) },
            edgeDistances: Dictionary(nearest.map { ($0.id, $0.edgeDistanceTo(anchor)) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// Logs what the OS actually holds, not what was asked for, so a rejected region or a starved
    /// movement trigger is visible. Sorted so replay output is stable.
    @discardableResult
    func logRegistration(registeredIds: Set<String>, anchor: LocationData, registerMovementTrigger: Bool, triggerRadius: Double) -> (accepted: [String], movementTrigger: Bool) {
        let movementTriggerId = GeofenceConstants.movementTriggerIdentifier
        let accepted = registeredIds.subtracting([movementTriggerId]).sorted()
        let movementTriggerAccepted = registeredIds.contains(movementTriggerId)
        logger.geofenceRegionsRegistered(
            identifiers: accepted,
            movementTrigger: movementTriggerAccepted ? movementTriggerId : nil
        )
        guard movementTriggerAccepted else { return (accepted, false) }
        logger.geofenceMovementTriggerRegistered(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            radius: triggerRadius
        )
        return (accepted, true)
    }
}
