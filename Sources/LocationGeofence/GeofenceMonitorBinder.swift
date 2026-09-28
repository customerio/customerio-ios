import CioInternalCommon
import Foundation

/// `bind` must run before any `startMonitoring`, so cold-wake callbacks find a handler.
@MainActor
enum GeofenceMonitorBinder {
    static func bind(
        monitor: GeofenceRegionMonitoring,
        resolver: PolygonMembershipResolver,
        coordinator: GeofenceSyncCoordinator,
        logger: Logger,
        backgroundTaskRunner: BackgroundTaskRunner = GeofenceBackgroundTime.runner(name: "io.customer.geofence.movement-pass")
    ) {
        monitor.setOnTransition { [weak resolver, weak coordinator] identifier, transition, location, occurredAt, locationIsFresh, eventCircle in
            if identifier == GeofenceConstants.movementTriggerIdentifier {
                guard transition == .exit else {
                    logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "movement_trigger_not_exit")
                    return
                }
                guard let location else {
                    logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "movement_trigger_no_location")
                    return
                }
                // Background time: the EXIT is consumed once dispatched and never retried.
                Task {
                    await backgroundTaskRunner.withBackgroundTime {
                        _ = await coordinator?.handleMovement(
                            latitude: location.latitude,
                            longitude: location.longitude,
                            anchorIsLiveFix: locationIsFresh,
                            heldFix: nil
                        )
                    }
                }
                return
            }
            // One Task: parallel dispatch would lose the coordinator's gate.
            Task {
                let outcome = await resolver?.handleTransition(
                    identifier: identifier, transition: transition,
                    occurredAt: occurredAt, eventCircle: eventCircle
                ) ?? .nothingToRearm

                await dispatchFollowUp(
                    outcome: outcome, coordinator: coordinator,
                    location: location, locationIsFresh: locationIsFresh,
                    backgroundTaskRunner: backgroundTaskRunner
                )
            }
        }
    }

    private static func dispatchFollowUp(
        outcome: PolygonTransitionOutcome,
        coordinator: GeofenceSyncCoordinator?,
        location: LocationData?,
        locationIsFresh: Bool,
        backgroundTaskRunner: BackgroundTaskRunner
    ) async {
        switch outcome {
        case .circleEntered(let fix):
            // `handleMovement`, not `refresh`: `refresh` skips until a full radius is moved and never
            // re-arms the trigger. The resolver's fix, not the callback's, which isn't fresh and
            // would widen the trigger.
            await backgroundTaskRunner.withBackgroundTime {
                // Pass the fix: re-evaluation needs one newer than the resolver's last (this one),
                // so a new request would come back empty.
                _ = await coordinator?.handleMovement(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    anchorIsLiveFix: true,
                    heldFix: fix
                )
                // Also refetches a time-expired catalog. Sequential: they share the gate.
                _ = await coordinator?.refresh(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    anchorIsLiveFix: true
                )
            }
        case .nothingToRearm:
            // Without this, a lost trigger EXIT leaves the catalog stale until the next app open.
            guard let location else { return }
            await backgroundTaskRunner.withBackgroundTime {
                _ = await coordinator?.refresh(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    anchorIsLiveFix: locationIsFresh
                )
            }
        }
    }

    /// Does NOT refresh the catalog: a visit's coordinate is minutes old, and `refresh` would widen
    /// the trigger where the tightest is needed.
    static func bindVisits(
        visitMonitor: GeofenceVisitMonitoring,
        resolver: PolygonMembershipResolver,
        contextStore: BackgroundDeliveryContextStore,
        backgroundTaskRunner: BackgroundTaskRunner = GeofenceBackgroundTime.runner(name: "io.customer.geofence.visit-pass")
    ) {
        visitMonitor.setOnVisit { [weak resolver] _ in
            // Read before the Task: the return value must reflect identity at the wake.
            guard let expectedUserId = contextStore.currentUserId else { return false }
            Task {
                await backgroundTaskRunner.withBackgroundTime {
                    // Forced fresh: the cached fix predates the arrival. Also bypasses the
                    // already-running short-circuit, as a visit may be the only wake.
                    await resolver?.evaluateAllPolygons(
                        reason: .visit,
                        requiresFreshFix: true,
                        isStillCurrent: { contextStore.currentUserId == expectedUserId }
                    )
                }
            }
            return true
        }
    }
}
