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
                && region.transitionTypes.contains(.enter)
                && region.distanceTo(anchor) <= min(region.radius, osRegistration.maxMonitoringRadius)
        }
        if !newPolygons.isEmpty {
            evaluateNewPolygons(newPolygons, expectedUserId: expectedUserId)
        }
        guard !newInside.isEmpty else { return }
        // Read outside the Task: `DateUtil` isn't Sendable, and Swift 5 mode doesn't diagnose it.
        let discoveredAt = dateUtil.now
        // Off the gate: a slow send must not stall the next refresh.
        Task { [transitionEmitter, contextStore, logger] in
            for region in newInside {
                // Per iteration: an awaited send can span a user switch.
                guard contextStore.currentUserId == expectedUserId else { return }
                logger.geofenceTransitionSynthesized(geofenceId: region.id, transition: .enter)
                await transitionEmitter.trackTransition(
                    geofenceId: region.id, transition: .enter, occurredAt: discoveredAt
                )
            }
        }
    }

    /// Forced-fresh: a cached fix would re-affirm the old verdict. Pass `heldFix` through; a new
    /// request would fail, as it needs a fix newer than the held one.
    func evaluatePolygonsAfterMovement(expectedUserId: String, heldFix: ResolvedFix? = nil) {
        Task { @MainActor [contextStore] in
            guard contextStore.currentUserId == expectedUserId else { return }
            await DIGraphShared.shared.polygonMembershipResolver.evaluateAllPolygons(
                reason: .movement,
                requiresFreshFix: true,
                heldFix: heldFix,
                isStillCurrent: { contextStore.currentUserId == expectedUserId }
            )
        }
    }

    private func evaluateNewPolygons(_ polygons: [Geofence], expectedUserId: String) {
        Task { @MainActor [contextStore] in
            guard contextStore.currentUserId == expectedUserId else { return }
            await DIGraphShared.shared.polygonMembershipResolver.evaluateNewlyRegistered(
                geofenceIds: polygons.map(\.id),
                isStillCurrent: { contextStore.currentUserId == expectedUserId }
            )
        }
    }
}
