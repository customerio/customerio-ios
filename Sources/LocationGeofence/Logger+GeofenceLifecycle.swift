import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

extension Logger {
    // MARK: - Registration

    func geofenceInvalidRegionDropped(_ identifier: String, reason: GeofenceRegionDropReason) {
        error(
            "Geofence '\(identifier)' dropped — \(reason.rawValue)"
                + geofenceTail("registration.rejected", .observation, [
                    ("id", identifier),
                    ("why", reason.logToken)
                ]),
            geofenceTag,
            nil
        )
    }

    func geofenceInvalidCoordinatesForRegion(_ identifier: String) {
        error(
            "Invalid coordinates for region \(identifier), skipping"
                + geofenceTail("registration.rejected", .observation, [
                    ("id", identifier),
                    ("why", "invalid_coordinates")
                ]),
            geofenceTag,
            nil
        )
    }

    // Pass `nil` as the error: the logger appends it after the tail, and the tail must stay last.
    func geofenceMonitoringFailed(region: String, error: Error) {
        self.error(
            "Monitoring failed for region \(region): \(error.localizedDescription)"
                + geofenceTail("os.monitor.failed", .input, [
                    ("id", region),
                    ("ok", GeofenceLog.bool(false))
                ]),
            geofenceTag,
            nil
        )
    }

    /// See `geofenceMonitoringFailed` for why the description is inlined rather than passed.
    func geofenceMonitorEventStreamFailed(error: Error) {
        self.error(
            "Geofence monitor event stream ended with an error; background transitions may stop until the app is relaunched: \(error.localizedDescription)"
                + geofenceTail("os.stream.failed", .input, [("ok", GeofenceLog.bool(false))]),
            geofenceTag,
            nil
        )
    }

    // `error` on purpose: lower levels aren't persisted for third-party subsystems.
    func geofenceMonitorStoppedMonitoringRegion(_ identifier: String) {
        error(
            "CoreLocation stopped monitoring region \(identifier); its transitions are not delivered until it is re-registered, which is now scheduled rather than left to the next sync"
                + geofenceTail("os.monitor.stopped", .input, [("id", identifier)]),
            geofenceTag,
            nil
        )
    }

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
                + geofenceTail("permission.changed", .input, [
                    ("perm", GeofenceLog.permission(currentStatus)),
                    ("why", "not_granted")
                ]),
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registered for foreground delivery only: WhenInUse authorization granted (current status: \(currentStatus.rawValue)). Background transitions require Always authorization."
                + geofenceTail("permission.changed", .input, [
                    ("perm", GeofenceLog.permission(currentStatus)),
                    ("why", "foreground_only")
                ]),
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryAvailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence background delivery active: Always authorization granted (current status: \(currentStatus.rawValue))."
                + geofenceTail("permission.changed", .input, [
                    ("perm", GeofenceLog.permission(currentStatus)),
                    ("ok", GeofenceLog.bool(true))
                ]),
            geofenceTag
        )
    }

    // MARK: - Lifecycle

    /// Always `app_start`; a cold wake logs `module.wake` separately, in no fixed order.
    func geofenceModuleInitialized(launchReason: GeofenceLaunchReason) {
        info(
            "Geofence module initialized (\(launchReason.rawValue))"
                + geofenceTail("module.init", .input, [("launch", launchReason.rawValue)]),
            geofenceTag
        )
    }

    func geofenceModuleWoke(launchReason: GeofenceLaunchReason) {
        info(
            "Geofence module woken (\(launchReason.rawValue))"
                + geofenceTail("module.wake", .input, [("launch", launchReason.rawValue)]),
            geofenceTag
        )
    }

    // MARK: - OS callback routing

    /// The OS sends no position, so `fix` is the SDK's own. `buf`: the event waited for a handler.
    func geofenceCallbackReceived(
        identifier: String,
        transition: GeofenceTransition,
        fix: CLLocation?,
        source: GeofenceLog.FixSource,
        eventDate: Date? = nil,
        buffered: Bool = false,
        now: Date
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
                        + GeofenceLog.fixQuality(fix, source: source, now: now)
                        + GeofenceLog.eventTiming(eventDate, now: now)
                        + GeofenceLog.position(fix)
                ),
            geofenceTag
        )
    }

    /// Outside the asserted vocabulary. Not `os.callback.dropped`: these have no
    /// `os.callback.received` to net against.
    func geofenceInfo(_ reason: String, fields: [(String, String?)] = []) {
        debug(
            "Geofence note: \(reason.replacingOccurrences(of: "_", with: " "))"
                + geofenceTail("info", .observation, [("why", reason)] + fields),
            geofenceTag
        )
    }

    func geofenceCallbackDropped(identifier: String, transition: GeofenceTransition, reason: String) {
        debug(
            "OS \(transition.rawValue) for region \(identifier) not routed: \(reason)"
                + geofenceTail("os.callback.dropped", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("why", reason)
                ]),
            geofenceTag
        )
    }

    /// The identifier is never written.
    func geofenceIdentityChanged(identified: Bool) {
        debug(
            "Geofence identity \(identified ? "identified" : "reset")"
                + geofenceTail("identity.changed", .input, [("ok", GeofenceLog.bool(identified))]),
            geofenceTag
        )
    }

    /// The only `location.fix` that is an arrival rather than a read.
    func geofenceLocationArrived(_ location: LocationData) {
        debug(
            "Location fix delivered to geofencing"
                + geofenceTail("location.fix", .input, GeofenceLog.position(location) + [
                    ("prov", GeofenceLog.FixSource.bus.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceLocationFix(_ location: CLLocation?, source: GeofenceLog.FixSource, now: Date) {
        guard GeofenceDiagnostics.isEnabled else { return }
        guard let location else {
            debug(
                "Deciding from no fix"
                    + geofenceTail("location.fix", .input, [("prov", GeofenceLog.FixSource.none.rawValue)]),
                geofenceTag
            )
            return
        }
        debug(
            "Deciding from \(source.rawValue) fix"
                + geofenceTail("location.fix", .input, GeofenceLog.position(location) + [
                    ("acc", GeofenceLog.num(location.horizontalAccuracy, 1)),
                    ("age", GeofenceLog.num(now.timeIntervalSince(location.timestamp), 6)),
                    ("prov", source.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceFixReceived(_ location: CLLocation, source: String, now: Date) {
        debug(
            "Location fix received (\(source))"
                + geofenceTail("fix.received", .observation, [
                    ("prov", source)
                ] + GeofenceLog.position(location) + [
                    ("acc", GeofenceLog.num(location.horizontalAccuracy, 1)),
                    ("age", GeofenceLog.num(now.timeIntervalSince(location.timestamp), 6))
                ]),
            geofenceTag
        )
    }

    // MARK: - Storage

    func geofenceStorageLoaded(regionCount: Int, hasAnchor: Bool) {
        debug(
            "Loaded \(regionCount) cached region(s) from storage"
                + geofenceTail("storage.loaded", .observation, [
                    ("n", GeofenceLog.int(regionCount)),
                    ("anchor", GeofenceLog.bool(hasAnchor))
                ]),
            geofenceTag
        )
    }

    /// Adds can drain after `registration.applied` is logged; callbacks before this compare against
    /// a baseline not yet written.
    func geofenceConditionAdded(identifier: String) {
        debug(
            "Condition \(identifier) added at the OS"
                + geofenceTail("condition.added", .observation, [("id", identifier)]),
            geofenceTag
        )
    }

    /// `op=readd`: removed only to re-add (CLMonitor ignores an add over a live identifier).
    func geofenceConditionRemoved(identifier: String, op: GeofenceLog.RemovalOp) {
        debug(
            "Condition \(identifier) removed at the OS (\(op.rawValue))"
                + geofenceTail("condition.removed", .observation, [
                    ("id", identifier),
                    ("op", op.rawValue)
                ]),
            geofenceTag
        )
    }
}
