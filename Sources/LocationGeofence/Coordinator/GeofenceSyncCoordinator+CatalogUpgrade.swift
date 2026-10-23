import CioInternalCommon
import Foundation

/// A catalog cached by an SDK older than dwell support reads as dwell-disabled whatever the server
/// now says, while its sync time and anchor are genuine, so neither refetch rule replaces it.
/// These passes fetch it once regardless; only a persisted response marks the catalog current
/// (`GeofenceStorage.setCachedGeofences`), so a failed, unreadable or superseded fetch retries.
extension GeofenceSyncCoordinatorImpl {
    /// `action` is what this pass does with a current catalog. A failed fetch still does it, for
    /// the user the pass started for only, so offline the upgraded SDK keeps its old behaviour.
    func performCatalogUpgradeRefresh(
        expectedUserId: String,
        anchor: LocationData,
        cachedConfig: GeofenceConfig?,
        anchorIsLiveFix: Bool,
        fallback action: RefreshAction
    ) async -> MovementPassOutcome {
        let remote = await performRemoteRefresh(
            expectedUserId: expectedUserId,
            anchor: anchor,
            cachedConfig: cachedConfig,
            anchorIsLiveFix: anchorIsLiveFix
        )
        guard case .failure = remote.result, contextStore.currentUserId == expectedUserId else { return remote }
        let fallback = await performRefreshAction(
            action,
            expectedUserId: expectedUserId,
            anchor: anchor,
            cachedConfig: cachedConfig,
            anchorIsLiveFix: anchorIsLiveFix
        )
        // The fallback may have moved the trigger even though the fetch failed.
        return MovementPassOutcome(result: remote.result, reCentred: fallback.reCentred)
    }

    func performRefreshAction(
        _ action: RefreshAction,
        expectedUserId: String,
        anchor: LocationData,
        cachedConfig: GeofenceConfig?,
        anchorIsLiveFix: Bool
    ) async -> MovementPassOutcome {
        switch action {
        case .remote:
            return await performRemoteRefresh(
                expectedUserId: expectedUserId,
                anchor: anchor,
                cachedConfig: cachedConfig,
                anchorIsLiveFix: anchorIsLiveFix
            )
        case .local:
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                expectedUserId: expectedUserId,
                anchor: anchor,
                config: cachedConfig ?? .fallback,
                cachedRegions: cachedRegions,
                anchorIsLiveFix: anchorIsLiveFix
            )
        // Moved nothing, so it must not retire a queued movement.
        case .skip:
            logger.geofenceSyncSkippedFresh()
            return MovementPassOutcome(result: .success(()), reCentred: false)
        }
    }

    /// A failed fetch falls back to the tier this movement would otherwise take, not the
    /// failed-refetch re-arm: a wake pass must not record a registration centre.
    func performCatalogUpgradeMovement(
        expectedUserId: String,
        movement: LocationData,
        cachedConfig: GeofenceConfig?,
        anchorIsLiveFix: Bool,
        heldFix: ResolvedFix?
    ) async -> MovementPassOutcome {
        logger.geofenceMovementTrigger(tier: .remoteRefresh)
        let remote = await performRemoteRefresh(
            expectedUserId: expectedUserId,
            anchor: movement,
            cachedConfig: cachedConfig,
            anchorIsLiveFix: anchorIsLiveFix,
            heldFix: heldFix
        )
        guard case .failure = remote.result, contextStore.currentUserId == expectedUserId else { return remote }
        let fallback = await performCachedMovementTier(
            expectedUserId: expectedUserId,
            movement: movement,
            config: cachedConfig ?? .fallback,
            anchorIsLiveFix: anchorIsLiveFix,
            heldFix: heldFix
        )
        return MovementPassOutcome(result: remote.result, reCentred: fallback.reCentred)
    }

    /// The movement tiers that need no fetch: a wake pass inside the re-rank radius, else a
    /// re-rank of the cache.
    func performCachedMovementTier(
        expectedUserId: String,
        movement: LocationData,
        config: GeofenceConfig,
        anchorIsLiveFix: Bool,
        heldFix: ResolvedFix?
    ) async -> MovementPassOutcome {
        guard await movedBeyondRerankRadius(to: movement, config: config) else {
            return await performPolygonWakePass(
                expectedUserId: expectedUserId,
                at: movement,
                config: config,
                anchorIsLiveFix: anchorIsLiveFix,
                heldFix: heldFix
            )
        }
        logger.geofenceMovementTrigger(tier: .localRerank)
        let cachedRegions = await storage.getCachedGeofences()
        return await performLocalRefresh(
            expectedUserId: expectedUserId,
            anchor: movement,
            config: config,
            cachedRegions: cachedRegions,
            anchorIsLiveFix: anchorIsLiveFix,
            heldFix: heldFix
        )
    }
}
