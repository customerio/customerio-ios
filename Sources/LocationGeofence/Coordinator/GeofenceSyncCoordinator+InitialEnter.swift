import CioInternalCommon
import Foundation

extension GeofenceSyncCoordinatorImpl {
    /// Neither OS monitor reports ENTER for a fence the device is already inside. Only fences the OS
    /// took, and not in `previouslyRegisteredIds`, so a re-register stays silent.
    func emitInitialEnters(
        candidates: [Geofence],
        osRegistration: GeofenceOsRegistration,
        previouslyRegisteredIds: Set<String>,
        expectedUserId: String,
        anchor: LocationData
    ) {
        let newlyRegistered = candidates.filter { region in
            osRegistration.registeredIds.contains(region.id)
                && !previouslyRegisteredIds.contains(region.id)
        }
        // Not polygons: `radius` is the covering circle, so the resolver evaluates them instead.
        let newPolygons = newlyRegistered.filter { $0.vertices != nil }
        let newInside = newlyRegistered.filter { region in
            region.vertices == nil
                && (region.transitionTypes.contains(.enter) || region.dwellThresholdSeconds > 0)
                && region.distanceTo(anchor) <= min(region.radius, osRegistration.maxMonitoringRadius)
        }
        if !newPolygons.isEmpty {
            evaluateNewPolygons(newPolygons, expectedUserId: expectedUserId)
        }
        guard !newInside.isEmpty else { return }
        // Read outside the Task: `DateUtil` isn't Sendable, and Swift 5 mode doesn't diagnose it.
        let discoveredAt = dateUtil.now
        // Off the gate: a slow send must not stall the next refresh. Not main-actor bound either, so
        // the ENTER can't queue behind a sign-out; only the visit bookkeeping hops, in a child run
        // alongside the emit — awaited after it, a stalled send left the visit unwritten past an EXIT.
        Task { [transitionEmitter, contextStore, logger, dwellCoordinator] in
            for region in newInside {
                // Per iteration: an awaited send can span a user switch.
                guard contextStore.currentUserId == expectedUserId else { return }
                async let visitRecorded: Void? = dwellCoordinator?.handleBoundary(
                    geofence: region,
                    transition: .enter,
                    occurredAt: discoveredAt,
                    expectedUserId: expectedUserId,
                    // Discovery, not a crossing: the stay began at some unknown earlier time, so
                    // `discoveredAt` is never a reported entry. Nor is presence proven: the anchor
                    // may be a stored location, and it carries no accuracy. The candidate counts
                    // time only from the first fresh fix wholly inside.
                    entryObserved: false,
                    presenceProven: false
                )
                if region.transitionTypes.contains(.enter) {
                    logger.geofenceTransitionSynthesized(geofenceId: region.id, transition: .enter)
                    await transitionEmitter.trackTransition(
                        geofenceId: region.id, transition: .enter, occurredAt: discoveredAt
                    )
                }
                _ = await visitRecorded
            }
        }
    }

    /// Forced-fresh: a cached fix would re-affirm the old verdict. Pass `heldFix` through; a new
    /// request would fail, as it needs a fix newer than the held one.
    func evaluatePolygonsAfterMovement(expectedUserId: String, heldFix: ResolvedFix? = nil) {
        Task { @MainActor [contextStore, polygonResolver] in
            guard contextStore.currentUserId == expectedUserId else { return }
            await polygonResolver().evaluateAllPolygons(
                reason: .movement,
                requiresFreshFix: true,
                heldFix: heldFix,
                isStillCurrent: { contextStore.currentUserId == expectedUserId }
            )
        }
    }

    private func evaluateNewPolygons(_ polygons: [Geofence], expectedUserId: String) {
        Task { @MainActor [contextStore, polygonResolver] in
            guard contextStore.currentUserId == expectedUserId else { return }
            await polygonResolver().evaluateNewlyRegistered(
                geofenceIds: polygons.map(\.id),
                isStillCurrent: { contextStore.currentUserId == expectedUserId }
            )
        }
    }
}
