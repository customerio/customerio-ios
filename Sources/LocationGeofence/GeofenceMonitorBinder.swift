import CioInternalCommon
import Foundation

/// Wires the monitor's transition handler. Synchronous — must run before any
/// `startMonitoring` call so cold-wake delegate callbacks arriving immediately after
/// `CLLocationManager` becomes active have a handler to dispatch to.
///
/// Two dispatch paths:
/// - `GeofenceConstants.movementTriggerIdentifier` (EXIT) → `coordinator.handleMovement`
///   (internal; never tracked as a customer event).
/// - Any other identifier → `resolver.handleTransition`, which forwards circle geofences to the
///   tracker unchanged and interprets a polygon's covering-circle event against membership. What
///   it answers then picks the follow-up: entering a polygon's covering circle re-arms the wake
///   against the boundary the OS cannot see, and everything else takes a throttled
///   `coordinator.refresh` so catalog freshness does not depend on the trigger EXIT alone.
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
            // CLLocationManager delivers on main; both handlers below are async with their
            // own serialization (tracker active-delivery dedup, coordinator refresh gate),
            // so fire-and-forget Tasks are safe.
            if identifier == GeofenceConstants.movementTriggerIdentifier {
                // EXIT is the only registered transition for the movement trigger; the
                // guard defends against an unexpected ENTER reaching this dispatch.
                guard transition == .exit else {
                    logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "movement_trigger_not_exit")
                    return
                }
                guard let location else {
                    logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "movement_trigger_no_location")
                    return
                }
                // The EXIT is consumed once dispatched; a wake window expiring mid-pass would
                // lose it with no retry, so the pass runs under a background-task assertion.
                // (The tracker path holds its own inside `trackTransition`.)
                Task {
                    await backgroundTaskRunner.withBackgroundTime {
                        _ = await coordinator?.handleMovement(
                            latitude: location.latitude,
                            longitude: location.longitude,
                            anchorIsLiveFix: locationIsFresh
                        )
                    }
                }
                return
            }
            // One Task, not two: the follow-up depends on what the resolver decided, and the two
            // share the coordinator's gate — dispatched in parallel, one of them loses it and
            // logs `refresh_in_progress` for work that was never redundant.
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
    ///
    /// Extracted from `bind` only to keep that closure inside the function-length cap; it is one
    /// step of the same dispatch.
    private static func dispatchFollowUp(
        outcome: PolygonTransitionOutcome,
        coordinator: GeofenceSyncCoordinator?,
        location: LocationData?,
        locationIsFresh: Bool,
        backgroundTaskRunner: BackgroundTaskRunner
    ) async {
        switch outcome {
        case .circleEntered(let fix):
            // Entering a polygon's covering circle puts the device beside a boundary the OS
            // cannot report, and the wake is sized at registration time — so without this
            // the device carries whatever trigger it arrived with. Measured: a circle entry
            // 45 m from the ring, then nothing for 11 minutes, because the trigger in force
            // was the full refresh radius from a registration made kilometres earlier.
            //
            // `handleMovement`, not `refresh`: `refresh` answers `.skip` unless the device
            // has moved a full refresh radius from the last registration centre, and `.skip`
            // never touches the trigger. `handleMovement` has a third tier for exactly this
            // case — `performPolygonWakePass`, which re-arms against the nearest boundary
            // and re-evaluates, with no ranking and no cache write.
            //
            // The resolver's fix, not the callback's: business events dispatch with
            // `locationIsFresh == false` on both monitor paths, and a non-live anchor makes
            // the coordinator widen the trigger to the full refresh radius — installing the
            // widest possible wake in the one case that needs the tightest.
            await backgroundTaskRunner.withBackgroundTime {
                _ = await coordinator?.handleMovement(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    anchorIsLiveFix: true
                )
                // `handleMovement` covers distance, never age: it refetches on
                // `movedBeyondRefetchRadius` or a missing anchor, while `refreshAction`
                // also answers `.remote` for a cache that merely EXPIRED. Without this a
                // circle entry with a time-expired catalog, made without moving a refetch
                // radius, would re-arm the wake and leave the catalog stale — narrower
                // than the crossing-refresh this path had before the re-arm was added.
                //
                // Sequential, not parallel: they share the coordinator's gate. Cheap in
                // the common case because the wake pass writes no `lastSync`, so this sees
                // the same freshness the decision table would have seen, and a refetch the
                // movement pass already did leaves nothing for it to answer `.remote` to.
                _ = await coordinator?.refresh(
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    anchorIsLiveFix: true
                )
            }
        case .nothingToRearm:
            // A business-fence crossing is still evidence the device moved, and the
            // catalog's only other refresh input is the movement trigger's EXIT. When that
            // EXIT is lost the cache has nothing left to recover it: there is no timer and
            // no background refresh, so it stays stale until the app is next opened —
            // measured at three hours in the field, and unbounded while the device stays
            // still.
            //
            // `refresh` here because nothing needs re-arming: it consults the same decision
            // table as app launch and answers `.skip` when nothing has moved or aged, so a
            // crossing that warrants no work costs one storage read.
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
}
