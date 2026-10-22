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
                && (
                    region.transitionTypes.contains(.enter) ||
                        region.dwellThresholdSeconds > 0 ||
                        region.transitionTypes.contains(.exit)
                )
                && region.distanceTo(anchor) <= min(region.radius, osRegistration.maxMonitoringRadius)
        }
        if !newPolygons.isEmpty {
            evaluateNewPolygons(newPolygons, expectedUserId: expectedUserId)
        }
        // Circles this refresh kept, with a dwell threshold: the OS reports no ENTER for a fence it
        // already holds the device inside, and enabling or changing the threshold while inside
        // prunes the visit (its revision changed), so nothing would restart one before the next
        // crossing. A candidate is started from discovery wherever the monitor holds the circle
        // entered; a visit that still exists is kept as it is.
        let keptWithDwell = candidates.filter { region in
            region.vertices == nil && region.dwellThresholdSeconds > 0
                && osRegistration.registeredIds.contains(region.id)
                && previouslyRegisteredIds.contains(region.id)
        }
        guard !newInside.isEmpty || !keptWithDwell.isEmpty else { return }
        // Read outside the Task: `DateUtil` isn't Sendable, and Swift 5 mode doesn't diagnose it.
        let discoveredAt = dateUtil.now
        // Off the gate: a slow send must not stall the next refresh. Not main-actor bound either; only
        // the visit bookkeeping hops. Each ENTER's visit, and its ENTER mark, is written before the
        // ENTER is tracked: run alongside the send, an EXIT routed meanwhile could find no visit to
        // close and report no visit; awaited after it, a stalled send left the visit unwritten past
        // an EXIT.
        Task { [transitionEmitter, contextStore, logger, dwellCoordinator, storage] in
            if !keptWithDwell.isEmpty, let dwellCoordinator {
                let records = await storage.getMonitorRegionRecords()
                for region in keptWithDwell where records[region.id]?.lastState == .enter {
                    guard contextStore.currentUserId == expectedUserId else { return }
                    await dwellCoordinator.handleBoundary(
                        geofence: region, transition: .enter, occurredAt: discoveredAt,
                        expectedUserId: expectedUserId, crossingObserved: false, presenceProven: false
                    )
                }
            }
            for region in newInside {
                // Per iteration: an awaited send can span a user switch.
                guard contextStore.currentUserId == expectedUserId else { return }
                await dwellCoordinator?.handleBoundary(
                    geofence: region,
                    transition: .enter,
                    occurredAt: discoveredAt,
                    expectedUserId: expectedUserId,
                    // Discovery, not a crossing: the stay began at some unknown earlier time, so
                    // `discoveredAt` is never a reported entry, so never a reported duration. Nor is
                    // presence proven: the anchor may be a stored location, and it carries no
                    // accuracy. The candidate counts time only from the first fresh fix wholly inside.
                    crossingObserved: false,
                    presenceProven: false
                )
                if region.transitionTypes.contains(.enter) {
                    // The visit write hops to the main actor, which a user switch can reach first.
                    guard contextStore.currentUserId == expectedUserId else { return }
                    logger.geofenceTransitionSynthesized(geofenceId: region.id, transition: .enter)
                    await transitionEmitter.trackTransition(
                        geofenceId: region.id, transition: .enter, occurredAt: discoveredAt
                    )
                }
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
