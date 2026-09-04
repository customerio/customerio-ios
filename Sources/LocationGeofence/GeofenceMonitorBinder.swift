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
///   tracker unchanged and interprets a polygon's covering-circle event against membership.
@MainActor
enum GeofenceMonitorBinder {
    static func bind(
        monitor: GeofenceRegionMonitoring,
        resolver: PolygonMembershipResolver,
        coordinator: GeofenceSyncCoordinator,
        backgroundTaskRunner: BackgroundTaskRunner = GeofenceBackgroundTime.runner(name: "io.customer.geofence.movement-pass")
    ) {
        monitor.setOnTransition { [weak resolver, weak coordinator] identifier, transition, location, occurredAt, locationIsFresh in
            // CLLocationManager delivers on main; both handlers below are async with their
            // own serialization (tracker active-delivery dedup, coordinator refresh gate),
            // so fire-and-forget Tasks are safe.
            if identifier == GeofenceConstants.movementTriggerIdentifier {
                // EXIT is the only registered transition for the movement trigger; the
                // guard defends against an unexpected ENTER reaching this dispatch.
                guard transition == .exit, let location else { return }
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
            Task { await resolver?.handleTransition(identifier: identifier, transition: transition, occurredAt: occurredAt) }
        }
    }
}
