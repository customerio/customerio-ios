import CioInternalCommon
import Foundation

/// Wires the monitor's transition handler. Synchronous, and must run before any
/// `startMonitoring` so cold-wake callbacks have a handler to dispatch to.
///
/// - Movement trigger EXIT → `coordinator.handleMovement`; never tracked as a customer event.
/// - Any other identifier → `resolver.handleTransition` (circles pass through, polygons are judged
///   against membership). Entering a polygon's covering circle then re-arms the wake against the
///   boundary; anything else takes a `coordinator.refresh` so catalog freshness does not depend
///   on the trigger EXIT alone.
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
            // Fire-and-forget Tasks are safe: the tracker and coordinator serialize on their own.
            if identifier == GeofenceConstants.movementTriggerIdentifier {
                // The trigger registers EXIT only.
                guard transition == .exit else {
                    logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "movement_trigger_not_exit")
                    return
                }
                guard let location else {
                    logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "movement_trigger_no_location")
                    return
                }
                // The EXIT is consumed once dispatched, so a wake window expiring mid-pass would
                // lose it with no retry. Hence the background-task assertion.
                Task {
                    await backgroundTaskRunner.withBackgroundTime {
                        _ = await coordinator?.handleMovement(
                            latitude: location.latitude,
                            longitude: location.longitude,
                            anchorIsLiveFix: locationIsFresh,
                            // No resolved fix yet; the pass requests its own.
                            heldFix: nil
                        )
                    }
                }
                return
            }
            // One Task, not two: the follow-up depends on the resolver's answer, and parallel
            // dispatch would lose the coordinator's gate to `refresh_in_progress`.
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

    /// Chooses what a delivered business crossing does about the wake and the catalog.
    private static func dispatchFollowUp(
        outcome: PolygonTransitionOutcome,
        coordinator: GeofenceSyncCoordinator?,
        location: LocationData?,
        locationIsFresh: Bool,
        backgroundTaskRunner: BackgroundTaskRunner
    ) async {
        switch outcome {
        case .circleEntered(let fix):
            // The wake is sized at registration, so without a re-arm the device keeps whatever
            // trigger it arrived with beside a boundary the OS cannot report.
            //
            // `handleMovement`, not `refresh`: `refresh` answers `.skip` until the device has
            // moved a full refresh radius, and `.skip` never touches the trigger. The polygon
            // wake tier re-arms against the nearest boundary with no ranking or cache write.
            //
            // The resolver's fix, not the callback's: business events carry
            // `locationIsFresh == false`, which would widen the trigger to the full radius.
            await backgroundTaskRunner.withBackgroundTime {
                // Pass the fix along: the re-evaluation demands one strictly newer than the
                // resolver's last, which is this one, so a fresh request would come back empty
                // and every polygon would record `no_usable_fix`.
                _ = await coordinator?.handleMovement(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    anchorIsLiveFix: true,
                    heldFix: fix
                )
                // `handleMovement` refetches on distance only; `refresh` also refetches a
                // time-expired catalog. Sequential because they share the coordinator's gate.
                // Usually a cheap `.skip`: the wake pass writes no `lastSync`.
                _ = await coordinator?.refresh(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    anchorIsLiveFix: true
                )
            }
        case .nothingToRearm:
            // A crossing is evidence the device moved. The catalog's only other background
            // refresh input is the trigger EXIT; with no timer, a lost EXIT leaves it stale
            // until the next app open. `refresh` answers `.skip` when nothing moved or aged,
            // so an idle crossing costs cached reads and no network.
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

    /// Wires the visit wake: re-judges every registered polygon against a fresh fix. A device
    /// already inside a covering circle crosses no edge, so no OS callback comes; a visit is the
    /// only wake that notices it has entered the polygon.
    ///
    /// Does NOT refresh the catalog. A visit's coordinate is minutes old, so `refresh` would size
    /// the trigger from a stored anchor and install the widest wake where the tightest is needed.
    static func bindVisits(
        visitMonitor: GeofenceVisitMonitoring,
        resolver: PolygonMembershipResolver,
        contextStore: BackgroundDeliveryContextStore,
        backgroundTaskRunner: BackgroundTaskRunner = GeofenceBackgroundTime.runner(name: "io.customer.geofence.visit-pass")
    ) {
        visitMonitor.setOnVisit { [weak resolver] _ in
            // Read before the Task: the return value is the disarm answer, and it must reflect
            // the identity at the wake.
            guard let expectedUserId = contextStore.currentUserId else { return false }
            Task {
                // The pass suspends to resolve a fix; without the assertion a short wake window
                // can lose it with no retry.
                await backgroundTaskRunner.withBackgroundTime {
                    // Forced fresh: a visit means the device ARRIVED, so the cached fix predates
                    // it. Forcing also bypasses the already-running short-circuit, since a visit
                    // may be this crossing's only wake. If CoreLocation echoes the same fix the
                    // pass decides nothing, which the next wake recovers; a pre-arrival fix
                    // would decide wrongly.
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
