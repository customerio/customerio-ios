import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

/// Setup, permissions and OS plumbing: was the SDK in a position to see the crossing at all.
extension Logger {
    // MARK: - Registration

    /// `reason` separates a shape this version cannot monitor from a payload it could not read;
    /// the difference decides whether the cache is cleared.
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

    // The error description is inlined and `nil` passed as the error: the logger appends
    // " Error: <desc>" after the tail, which would break the parser's `key=value` split. The tail
    // has to stay last.
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

    // Error level on purpose: `info`/`debug` are not persisted to the log store for third-party
    // subsystems, so a field report would not carry them.
    func geofenceMonitorStoppedMonitoringRegion(_ identifier: String) {
        error(
            "CoreLocation stopped monitoring region \(identifier); its transitions are not delivered until it is re-registered, which is now scheduled rather than left to the next sync"
                + geofenceTail("os.monitor.stopped", .input, [("id", identifier)]),
            geofenceTag,
            nil
        )
    }

    /// Which regions are registered with the OS right now. Carries identifiers, not just a count,
    /// so a missed crossing can be checked against what was monitored.
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

    /// The module came up. Always `app_start`; a cold wake announces itself separately via
    /// ``geofenceModuleWoke(launchReason:)`` rather than racing this one for a single record.
    func geofenceModuleInitialized(launchReason: GeofenceLaunchReason) {
        info(
            "Geofence module initialized (\(launchReason.rawValue))"
                + geofenceTail("module.init", .input, [("launch", launchReason.rawValue)]),
            geofenceTag
        )
    }

    /// The process was started *by* something (a location event). Separate from `module.init`
    /// because the OS decides their order.
    func geofenceModuleWoke(launchReason: GeofenceLaunchReason) {
        info(
            "Geofence module woken (\(launchReason.rawValue))"
                + geofenceTail("module.wake", .input, [("launch", launchReason.rawValue)]),
            geofenceTag
        )
    }

    // MARK: - OS callback routing

    /// An OS-delivered crossing, logged in the monitor: the OS supplies no position with a geofence
    /// event, so the attached coordinate is the SDK's own best known fix, and the monitor is the
    /// last place holding it as a full `CLLocation` (accuracy, age, provenance).
    ///
    /// - Parameters:
    ///   - fix: the position the SDK will attach to this transition, whatever its quality.
    ///   - source: which cache or request that fix came from.
    ///   - eventDate: when the OS says the crossing happened, where it says so.
    ///   - buffered: whether the event waited in the pending queue for a handler to be bound.
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

    /// A note for humans explaining a capture, outside the asserted vocabulary (`ev=info`, `io=obs`).
    /// Not `os.callback.dropped`: every real drop nets against an `os.callback.received`, and these
    /// have no receipt to net against.
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

    /// A sign-in or sign-out reaching the geofence module. The identifier is never written.
    func geofenceIdentityChanged(identified: Bool) {
        debug(
            "Geofence identity \(identified ? "identified" : "reset")"
                + geofenceTail("identity.changed", .input, [("ok", GeofenceLog.bool(identified))]),
            geofenceTag
        )
    }

    /// A position the Location module delivered: the one `location.fix` that is an arrival.
    func geofenceLocationArrived(_ location: LocationData) {
        debug(
            "Location fix delivered to geofencing"
                + geofenceTail("location.fix", .input, GeofenceLog.position(location) + [
                    ("prov", GeofenceLog.FixSource.bus.rawValue)
                ]),
            geofenceTag
        )
    }

    /// A position the SDK read from the OS cache. `io=in`: the read is when the data crosses in.
    ///
    /// Gated whole: it fires on every cache read, and without the tail the line carries nothing.
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

    /// Every fix the SDK receives, with the accuracy and age it was judged on.
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

    /// What survived a cold start: whether a background wake had anything to work from.
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

    /// The moment one condition landed at the OS, one record per `CLMonitor.add`.
    ///
    /// The boundary a replay has to wait on: adds run one at a time through
    /// `enqueueMonitorOperation` and can drain after `registration.applied` is logged, so callbacks
    /// in that window compare against a baseline not yet written.
    ///
    /// Per identifier, unlike Android's count-carrying pair: CLMonitor takes one condition at a
    /// time. `registration.applied` remains the assertion; this is the mechanism under it.
    func geofenceConditionAdded(identifier: String) {
        debug(
            "Condition \(identifier) added at the OS"
                + geofenceTail("condition.added", .observation, [("id", identifier)]),
            geofenceTag
        )
    }

    /// The moment one condition left the OS. CLMonitor ignores an add over a live identifier, so
    /// every re-registration removes first; `op=readd` marks a condition on its way back in.
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
