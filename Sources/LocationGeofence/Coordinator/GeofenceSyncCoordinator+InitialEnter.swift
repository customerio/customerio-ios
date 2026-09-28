import CioInternalCommon
import Foundation

/// Initial enter-when-inside and post-registration polygon evaluation. Internal only because it
/// lives in a separate file from its callers.
extension GeofenceSyncCoordinatorImpl {
    /// Fires an initial ENTER for each newly registered geofence the device is already inside, which
    /// neither OS monitor reports (parity with Android's `INITIAL_TRIGGER_ENTER`). The
    /// `previouslyRegisteredIds` diff keeps a re-register silent; sign-out clears that set so the next
    /// sign-in re-fires. Done here so both monitor paths match.
    ///
    /// - Parameter osRegistration: what the OS accepted. A candidate it didn't take must not emit an
    ///   enter it can't balance, and the inside check clamps to `maxMonitoringRadius` (Apple
    ///   guarantees no floor for it, so a fence radius can exceed the monitored circle).
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
        // Polygons skip this containment test: `radius` is the covering circle, so a device in the
        // gap between circle and polygon would get an unearned enter. The resolver evaluates them.
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
        // Delivered off the gate so a slow send can't stall the next refresh; `trackTransition`
        // persists first, so an interrupted send is retried. No crossing happened, so the moment we
        // noticed is the event time. Read outside the Task: `DateUtil` isn't Sendable, and Swift 5
        // mode doesn't diagnose capturing it.
        let discoveredAt = dateUtil.now
        Task { [transitionEmitter, contextStore, logger] in
            for region in newInside {
                // Per iteration: an awaited send can span a user switch, and the tracker stamps the
                // current user.
                guard contextStore.currentUserId == expectedUserId else { return }
                // Downstream this looks like a real crossing; the log is the only thing that marks it
                // synthesized.
                logger.geofenceTransitionSynthesized(geofenceId: region.id, transition: .enter)
                await transitionEmitter.trackTransition(
                    geofenceId: region.id, transition: .enter, occurredAt: discoveredAt
                )
            }
        }
    }

    /// Re-evaluates polygon membership on a forced-fresh fix. The pass runs because the device moved,
    /// so a cached fix describes where it was and would re-affirm the old verdict.
    ///
    /// `heldFix` is a fix the caller already obtained under that rule. Requesting again would fail:
    /// the forced-fresh request needs a fix strictly newer than the last one the resolver delivered,
    /// which is the held one (see `PolygonMembershipResolver.heldFixUse`).
    func evaluatePolygonsAfterMovement(expectedUserId: String, heldFix: ResolvedFix? = nil) {
        Task { @MainActor [contextStore] in
            guard contextStore.currentUserId == expectedUserId else { return }
            // Also re-checked inside, after the fix resolves and before the emit.
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
            // Also re-checked inside, after the fix resolves.
            await DIGraphShared.shared.polygonMembershipResolver.evaluateNewlyRegistered(
                geofenceIds: polygons.map(\.id),
                isStillCurrent: { contextStore.currentUserId == expectedUserId }
            )
        }
    }
}
