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

    /// `reason` distinguishes a shape this version cannot monitor from a payload it could not read
    /// — the difference decides whether the cache is cleared, so a drive has to show which it was.
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

    // The description is inlined into the prose and `nil` passed for the error, rather than
    // handed to the logger. `Logger.formatMessage` appends " Error: <desc>" to the *whole*
    // message, which lands after the tail and leaves the remainder past the last `||` no longer
    // entirely `key=value` — dropping every field on the two records that explain why background
    // delivery stopped. The tail has to stay last.
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

    // Logged at error level deliberately: `info`/`debug` are not persisted to the log store for
    // third-party subsystems, so a field report would not carry them.
    func geofenceMonitorStoppedMonitoringRegion(_ identifier: String) {
        error(
            "CoreLocation stopped monitoring region \(identifier); its transitions are not delivered until it is re-registered, which is now scheduled rather than left to the next sync"
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

    /// The process was started *by* something — a location event today. A separate record from
    /// `module.init` because they are separate facts, and the OS decides their order.
    func geofenceModuleWoke(launchReason: GeofenceLaunchReason) {
        info(
            "Geofence module woken (\(launchReason.rawValue))"
                + geofenceTail("module.wake", .input, [("launch", launchReason.rawValue)]),
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

    /// Something worth reading in a log, deliberately outside the asserted vocabulary.
    ///
    /// `ev=info` is the bucket for records a human wants when explaining a capture but a scenario
    /// must never assert on. Two reasons it exists rather than reusing a semantic key:
    ///
    /// - Unexpected cases do not deserve invented semantics. Minting `os.callback.unusable` for
    ///   every oddity grows the vocabulary faster than anyone can keep it aligned across platforms.
    /// - More importantly, the obvious reuse is actively wrong. Filing these under
    ///   `os.callback.dropped` would inflate the received-vs-dropped count — the count that
    ///   separates "the OS never reported it" from "we discarded it", which is the question a
    ///   paired drive exists to answer. Every real `os.callback.dropped` nets against an
    ///   `os.callback.received`; these have no receipt to net against.
    ///
    /// `io=obs`, so the off-device transform drops the whole family rather than replaying it.
    func geofenceInfo(_ reason: String, fields: [(String, String?)] = []) {
        debug(
            "Geofence note: \(reason.replacingOccurrences(of: "_", with: " "))"
                + geofenceTail("info", .observation, [("why", reason)] + fields),
            geofenceTag
        )
    }

    /// The SDK re-registering conditions CoreLocation gave up on, instead of waiting for a
    /// movement pass that — when the trigger is among them — can never come.
    ///
    /// Error level for the same reason as `os.monitor.stopped` above, and it is the other half of
    /// that pair: `info` is not persisted to the log store for third-party subsystems, so a field
    /// report carried the outage and not the recovery, which reads as an outage that never ended.
    func geofenceUnmonitoredRecovery(count: Int) {
        error(
            "CoreLocation gave up \(count) condition(s); re-registering them now"
                + geofenceTail("registration.recovery", .observation, [
                    ("n", GeofenceLog.int(count)),
                    ("why", "os_unmonitored")
                ]),
            geofenceTag,
            nil
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
    /// Gated whole, not just in its tail. This fires on every cache read — 55 of them in nine
    /// minutes on the 2026-09-14 drive, against 11 OS callbacks — and with diagnostics off
    /// `geofenceTail` returns nothing, so the line that survived carried no position, accuracy, age
    /// or provenance. Volume with nothing in it, on a path this PR describes as logging-only.
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

    /// Every fix the SDK receives. Only the movement-pass fix age is logged today, so the
    /// positions the SDK was actually working from are invisible.
    func geofenceFixReceived(_ location: CLLocation, source: String) {
        debug(
            "Location fix received (\(source))"
                + geofenceTail("fix.received", .observation, [
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
                + geofenceTail("storage.loaded", .observation, [
                    ("n", GeofenceLog.int(regionCount)),
                    ("anchor", GeofenceLog.bool(hasAnchor))
                ]),
            geofenceTag
        )
    }

    /// The moment one condition actually landed at the OS — one record per `CLMonitor.add`.
    ///
    /// **The boundary a replay has to park on.** Every add runs inside `enqueueMonitorOperation`,
    /// so a sync's conditions reach CoreLocation one at a time behind whatever the queue already
    /// held — and the storage write that reseeds a condition's dedup baseline sits at the head of
    /// each add's own operation. On the 2026-09-12 iPhone relaunch that queue was still draining
    /// 170 ms after `registration.applied` was logged, so two callbacks landing inside the window
    /// compared against a baseline the phone had not written yet and a third arrived before an
    /// `.unmonitored`'s queued clear could run. Nothing recorded when any of those calls returned,
    /// so a replay answered them all instantly and decided differently — twice.
    ///
    /// Per identifier rather than per batch, unlike Android's count-carrying pair: CLMonitor takes
    /// one condition at a time, so the identifier is free and it pairs a recorded moment with the
    /// exact call a replay has to hold.
    ///
    /// `registration.applied` still reports the resulting set and is still the only assertion; this
    /// is the mechanism underneath it, the same relation `registration.diff` already has.
    func geofenceConditionAdded(identifier: String) {
        debug(
            "Condition \(identifier) added at the OS"
                + geofenceTail("condition.added", .observation, [("id", identifier)]),
            geofenceTag
        )
    }

    /// The moment one condition left the OS.
    ///
    /// `op` separates the two callers, which a reader cannot otherwise tell apart: CLMonitor
    /// silently ignores an add over a live identifier and keeps the original circle, so every
    /// re-registration removes first — a `readd` here is a condition on its way back in, not one
    /// going away. Counterpart to `geofenceConditionAdded`; see its note for why both exist.
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
