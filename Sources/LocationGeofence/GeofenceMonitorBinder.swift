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
        dwellCoordinator: GeofenceDwellCoordinator? = nil,
        backgroundTaskRunner: BackgroundTaskRunner = GeofenceBackgroundTime.runner(name: "io.customer.geofence.movement-pass")
    ) {
        // Dated here, synchronously: a visit entered before the removal task runs is not one the
        // loss interrupted.
        monitor.setOnMonitoringInterrupted { [weak dwellCoordinator] geofenceId in
            dwellCoordinator?.interruptContinuity(geofenceId: geofenceId)
        }
        monitor.setOnTransition { [weak resolver, weak coordinator, weak dwellCoordinator] identifier, transition, location, occurredAt, locationIsFresh, eventCircle, entryObserved in
            // Before the re-arm below: evidence it requests must not qualify a visit this ENTER
            // supersedes ahead of the task that routes the ENTER. Not for a replaced circle's
            // ENTER: it crossed no circle the stay is measured against.
            if transition == .enter {
                if eventCircle != .expired {
                    noteEnter(dwellCoordinator, geofenceId: identifier, occurredAt: occurredAt, crossing: entryObserved)
                }
            } else if transition == .exit, identifier != GeofenceConstants.movementTriggerIdentifier {
                // Before the re-arm too: until the task below routes this EXIT, it holds back a
                // first DWELL that evidence requested meanwhile would admit across it.
                noteExit(dwellCoordinator, geofenceId: identifier, occurredAt: occurredAt)
            }
            rearmDwellEvidence(dwellCoordinator)
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
            // Before the Task hop: a sign-in switch can run before the task does, and the crossing
            // belongs to whoever was identified when the OS delivered it.
            let receivedForUserId = resolver?.identifiedUserId ?? ""
            // One Task: parallel dispatch would lose the coordinator's gate.
            Task { [dwellCoordinator] in
                let outcome = await resolver?.handleTransition(
                    identifier: identifier, transition: transition,
                    occurredAt: occurredAt, eventCircle: eventCircle,
                    receivedForUserId: receivedForUserId, entryObserved: entryObserved
                ) ?? .nothingToRearm
                // Whatever the resolver made of it, this EXIT is no longer being routed.
                if transition == .exit { await dwellCoordinator?.exitCallbackRouted(geofenceId: identifier, occurredAt: occurredAt) }

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
        dwellCoordinator: GeofenceDwellCoordinator? = nil,
        backgroundTaskRunner: BackgroundTaskRunner = GeofenceBackgroundTime.runner(name: "io.customer.geofence.visit-pass")
    ) {
        visitMonitor.setOnVisit { [weak resolver, weak dwellCoordinator] _ in
            // Read before the Task: the return value must reflect identity at the wake.
            guard let expectedUserId = contextStore.currentUserId else { return false }
            // A visit reports the device stayed somewhere, which is exactly when a circle dwell
            // that came due during suspension needs its evidence.
            rearmDwellEvidence(dwellCoordinator)
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

    /// The OS invokes the transition handler on the main actor, though not statically isolated.
    /// `crossing` is the ENTER's `entryObserved`: a correction or heal is noted apart from crossings.
    private nonisolated static func noteEnter(
        _ dwellCoordinator: GeofenceDwellCoordinator?,
        geofenceId: String,
        occurredAt: Date,
        crossing: Bool
    ) {
        guard let dwellCoordinator else { return }
        MainActor.assumeIsolated {
            dwellCoordinator.noteEnter(geofenceId: geofenceId, occurredAt: occurredAt, crossing: crossing)
        }
    }

    /// See `noteEnter`: the same main-actor contract, for an EXIT's callback.
    private nonisolated static func noteExit(
        _ dwellCoordinator: GeofenceDwellCoordinator?,
        geofenceId: String,
        occurredAt: Date
    ) {
        guard let dwellCoordinator else { return }
        MainActor.assumeIsolated {
            dwellCoordinator.noteExitCallback(geofenceId: geofenceId, occurredAt: occurredAt)
        }
    }

    /// A background wake is the only chance a circle deadline gets while the app is suspended;
    /// see `GeofenceDwellCoordinator.rearmPendingEvidence`. Polygons are left to the resolver's own
    /// passes. Nonisolated because the OS callbacks calling it are.
    private nonisolated static func rearmDwellEvidence(_ dwellCoordinator: GeofenceDwellCoordinator?) {
        guard let dwellCoordinator else { return }
        Task { await dwellCoordinator.rearmPendingEvidence(includePolygons: false) }
    }
}
