import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

/// Setup, permissions and OS plumbing.
///
/// Split from `Logger+Geofence.swift` — which covers the crossing and sync pipeline — because the
/// two are read at different times: this file answers "was the SDK even in a position to see the
/// crossing", the other answers "what did it do about it".
extension Logger {
    // MARK: - Registration

    func geofenceInvalidRegionDropped(_ identifier: String) {
        error(
            "Geofence '\(identifier)' dropped — invalid coordinates or radius, not registerable with the OS"
                + geofenceTail("registration.rejected", .output, [
                    ("id", identifier),
                    ("why", "invalid_geometry")
                ]),
            geofenceTag,
            nil
        )
    }

    func geofenceInvalidCoordinatesForRegion(_ identifier: String) {
        error(
            "Invalid coordinates for region \(identifier), skipping"
                + geofenceTail("registration.rejected", .output, [
                    ("id", identifier),
                    ("why", "invalid_coordinates")
                ]),
            geofenceTag,
            nil
        )
    }

    func geofenceMonitoringFailed(region: String, error: Error) {
        self.error(
            "Monitoring failed for region \(region)"
                + geofenceTail("os.monitor.failed", .input, [
                    ("id", region),
                    ("ok", GeofenceLog.bool(false))
                ]),
            geofenceTag,
            error
        )
    }

    func geofenceMonitorEventStreamFailed(error: Error) {
        self.error(
            "Geofence monitor event stream ended with an error; background transitions may stop until the app is relaunched"
                + geofenceTail("os.stream.failed", .input, [("ok", GeofenceLog.bool(false))]),
            geofenceTag,
            error
        )
    }

    // Logged at error level deliberately: `info`/`debug` are not persisted to the log store for
    // third-party subsystems, so a field report would not carry them.
    func geofenceMonitorStoppedMonitoringRegion(_ identifier: String) {
        error(
            "CoreLocation stopped monitoring region \(identifier); its transitions are not delivered until the next sync re-registers it"
                + geofenceTail("os.monitor.stopped", .input, [("id", identifier)]),
            geofenceTag,
            nil
        )
    }

    /// Which regions are actually registered with the OS right now.
    ///
    /// Counts alone cannot answer the first question anyone asks of a drive that missed a
    /// crossing — "was this geofence even being monitored when I drove through it?" — so the
    /// identifiers travel too.
    func geofenceRegionsRegistered(identifiers: [String], movementTrigger: String?) {
        debug(
            "Monitoring \(identifiers.count) region(s) with the OS"
                + geofenceTail("registration.applied", .output, [
                    ("n", GeofenceLog.int(identifiers.count)),
                    ("ids", GeofenceLog.list(identifiers.sorted())),
                    ("mvmt", movementTrigger)
                ]),
            geofenceTag
        )
    }

    // MARK: - Permissions

    func geofencePermissionUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registration skipped: location permission not granted (current status: \(currentStatus.rawValue)). The host app controls when and which permission to request."
                + geofenceTail("permission.changed", .observation, [
                    ("perm", GeofenceLog.permission(currentStatus)),
                    ("why", "not_granted")
                ]),
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registered for foreground delivery only: WhenInUse authorization granted (current status: \(currentStatus.rawValue)). Background transitions require Always authorization."
                + geofenceTail("permission.changed", .observation, [
                    ("perm", GeofenceLog.permission(currentStatus)),
                    ("why", "foreground_only")
                ]),
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryAvailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence background delivery active: Always authorization granted (current status: \(currentStatus.rawValue))."
                + geofenceTail("permission.changed", .observation, [
                    ("perm", GeofenceLog.permission(currentStatus)),
                    ("ok", GeofenceLog.bool(true))
                ]),
            geofenceTag
        )
    }

    // MARK: - Lifecycle

    /// Process start and why. A background wake and a user opening the app look identical in the
    /// log today, and they are the two cases whose behaviour differs most.
    func geofenceModuleInitialized(launchReason: GeofenceLaunchReason) {
        info(
            "Geofence module initialized (\(launchReason.rawValue))"
                + geofenceTail("module.init", .observation, [("launch", launchReason.rawValue)]),
            geofenceTag
        )
    }

    // MARK: - OS callback routing

    /// An OS-delivered crossing, logged in the monitor rather than further down the pipeline.
    ///
    /// The OS supplies **no position** with a geofence event on either path — `CLMonitor.Event` is
    /// identifier, state and date; the classic delegate gets a `CLRegion`. The coordinate attached
    /// to a transition is therefore always the SDK's own best known fix, and the monitor is the
    /// last place that still holds it as a full `CLLocation`. One line later it has been narrowed
    /// to two doubles and the accuracy, age and provenance are gone.
    ///
    /// - Parameters:
    ///   - fix: the position the SDK will attach to this transition, whatever its quality.
    ///   - source: which cache or request that fix came from.
    ///   - eventDate: when the OS says the crossing happened, where it says so. The gap between
    ///     this and now separates "observed late" from "observed on time, delivered late" — two
    ///     faults that look identical without it.
    ///   - buffered: whether the event waited in the pending queue for a handler to be bound.
    func geofenceCallbackReceived(
        identifier: String,
        transition: GeofenceTransition,
        fix: CLLocation?,
        source: GeofenceLog.FixSource,
        eventDate: Date? = nil,
        buffered: Bool = false
    ) {
        debug(
            "OS reported \(transition.rawValue) for region \(identifier)"
                + geofenceTail(
                    "os.callback.received",
                    .input,
                    [
                        ("id", identifier),
                        ("t", transition.rawValue),
                        ("buf", GeofenceLog.bool(buffered))
                    ]
                        + GeofenceLog.fixQuality(fix, source: source)
                        + GeofenceLog.eventTiming(eventDate)
                        + GeofenceLog.position(fix)
                ),
            geofenceTag
        )
    }

    func geofenceCallbackDropped(identifier: String, transition: GeofenceTransition, reason: String) {
        debug(
            "OS \(transition.rawValue) for region \(identifier) not routed: \(reason)"
                + geofenceTail("os.callback.dropped", .input, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("why", reason)
                ]),
            geofenceTag
        )
    }

    /// Every fix the SDK receives. Only the movement-pass fix age is logged today, so the
    /// positions the SDK was actually working from are invisible.
    func geofenceFixReceived(_ location: CLLocation, source: String) {
        debug(
            "Location fix received (\(source))"
                + geofenceTail("fix.received", .input, [
                    ("prov", source)
                ] + GeofenceLog.position(location)),
            geofenceTag
        )
    }

    // MARK: - Storage

    /// What survived a cold start. Answers whether a background wake had anything to work from at
    /// all, which is otherwise guesswork.
    func geofenceStorageLoaded(regionCount: Int, hasAnchor: Bool) {
        debug(
            "Loaded \(regionCount) cached region(s) from storage"
                + geofenceTail("storage.loaded", .input, [
                    ("n", GeofenceLog.int(regionCount)),
                    ("anchor", GeofenceLog.bool(hasAnchor))
                ]),
            geofenceTag
        )
    }
}
