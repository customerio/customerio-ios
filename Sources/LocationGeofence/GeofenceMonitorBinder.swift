import CioInternalCommon
import Foundation

/// Wires the monitor's transition handler. Synchronous — must run before any
/// `startMonitoring` call so cold-wake delegate callbacks arriving immediately after
/// `CLLocationManager` becomes active have a handler to dispatch to.
///
/// Three dispatch paths:
/// - `GeofenceConstants.movementTriggerIdentifier` (EXIT) → `coordinator.handleMovement`
///   (internal; never tracked as a customer event).
/// - A polygon's tripwire (EXIT) → `resolver.evaluateMembership` (internal; the wake that lets the
///   SDK re-check membership inside a covering circle, where the OS is silent).
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
        monitor.setOnTransition { [weak resolver, weak coordinator] identifier, transition, location in
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
                        _ = await coordinator?.handleMovement(latitude: location.latitude, longitude: location.longitude)
                    }
                }
                return
            }
            if let polygonId = GeofenceInternalIdentifier.geofenceId(forTripwire: identifier) {
                // A tripwire is planted around the device to provoke a wake once it has moved far
                // enough to change the verdict; only leaving it carries information. Held under a
                // background-task assertion for the same reason the movement pass is — the wake
                // window can expire mid-evaluation, and nothing re-delivers a consumed EXIT.
                guard transition == .exit else { return }
                Task {
                    await backgroundTaskRunner.withBackgroundTime {
                        await resolver?.evaluateMembership(
                            geofenceId: polygonId, reason: "tripwire wake", requiresFreshFix: true
                        )
                    }
                }
                return
            }
            Task { await resolver?.handleTransition(identifier: identifier, transition: transition, location: location) }
        }
    }
}
