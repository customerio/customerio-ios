import CioInternalCommon
import Foundation

extension GeofenceSyncCoordinatorImpl {
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
        // Read before `recordRegistration` overwrites it.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        let wakeRadius = wakeRadius(at: anchor, polygons: nearest, config: effectiveConfig, anchorIsLiveFix: anchorIsLiveFix)
        logRanking(candidates: regions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        // Before registering: the OS can report a newly added fence before the cache below holds
        // it, and a widened edge must already be known as bookkeeping when it does.
        await storage.recordRegistrationIntent(for: regions, pruningToCache: true)
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
        if let parsedConfig {
            await storage.setCachedConfig(parsedConfig)
            onConfigPersisted.wrappedValue?()
        }
        await storage.recordSync(timestamp: dateUtil.now, location: anchor)
        // Only what the OS accepted, or the resolver could emit an enter no exit can balance.
        await storage.recordRegistration(center: anchor, businessIds: registeredIds)
    }

    /// No `lastSync` write: the refetch decision measures from the fetch anchor.
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
        // Read before `recordRegistration` overwrites it.
        let previouslyRegisteredIds = await storage.getRegisteredBusinessIds()
        let nearestIds = Set(nearest.map(\.id))
        logRanking(candidates: cachedRegions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let wakeRadius = wakeRadius(at: anchor, polygons: nearest, config: config, anchorIsLiveFix: anchorIsLiveFix)
        // Additive only: the cache is what is registered here, and a cache written before this
        // record existed must not register a widened edge that nothing marks as bookkeeping.
        await storage.recordRegistrationIntent(for: cachedRegions, pruningToCache: false)
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

    /// Must not `recordRegistration`: see `movedBeyondRerankRadius`.
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

    /// Boundary-sized only for a live fix: around a stored anchor it may already exclude the device.
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

    /// Fails when none survive and any was unreadable, or a broken payload would deregister
    /// everything. Unsupported shapes don't count, so they can't freeze stale fences forever.
    private func readableRegions(from response: GeofenceApiResponse) -> Result<[Geofence], GeofenceSyncError> {
        var unreadableCount = 0
        let regions = response.toDomainRegions(onInvalidRegion: { id, reason in
            logger.geofenceInvalidRegionDropped(id, reason: reason)
            // `unknownShape` is unsupported, not unreadable; `undescribedShape` is malformed and
            // counts.
            if reason != .unknownShape { unreadableCount += 1 }
        })
        // Regions lost at JSON decode never reach `toDomainRegions`.
        let decodeLosses = response.receivedRegionCount - response.geofences.count
        guard regions.isEmpty, unreadableCount + decodeLosses > 0 else { return .success(regions) }
        logger.geofenceAllRegionsDropped(count: response.receivedRegionCount)
        return .failure(.fetchFailed(.decoding))
    }

    /// Call with the gate still held: a sign-out's `reset()` is dropped while it is held, so this
    /// undoes the stale user's state.
    func cleanupIfUserChanged(expectedUserId: String?) async -> Bool {
        guard let expectedUserId, contextStore.currentUserId != expectedUserId else { return false }
        // Clear before the OS stop — same ordering rule as `reset`, same reason.
        await storage.clearUserScopedState()
        await MainActor.run { monitor.stopMonitoringAll() }
        logger.geofenceSyncSupersededByUserChange()
        return true
    }

    // MARK: - Diagnostics

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

    /// Sorted so replay output is stable.
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
