import CioInternalCommon
import CoreLocation
import Foundation

/// Cached-fix reads for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable (same convention as `+Registration`).
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor: GeofenceFixSelecting {
    /// `GeofenceFixSelecting`; `bestKnownFix()` and `bestKnownFixDetail()` come from its default.
    var osCachedFix: CLLocation? { authManager.location }

    /// Records an OS-delivered crossing together with the fix the SDK will attach to it.
    ///
    /// Lives here rather than inline at the event handler because this is where the full
    /// `CLLocation` and its provenance are known — and because the handler is already at the
    /// file-length limit.
    func logReceivedCallback(identifier: String, transition: GeofenceTransition, eventDate: Date?) {
        let detail = bestKnownFixDetail()
        logger.geofenceCallbackReceived(
            identifier: identifier,
            transition: transition,
            fix: detail?.fix,
            source: detail?.source ?? .none,
            eventDate: eventDate
        )
    }

    /// Records a crossing the dedup baseline discarded, and why.
    ///
    /// Same reason `logReceivedCallback` lives here: the handler is at the file-length limit. And
    /// the same reason it exists at all — CLMonitor delivers a crossing more than once (a field
    /// drive saw every one arrive twice, 8-10 ms apart with identical fixes), and the duplicate is
    /// absorbed by the baseline. Without this the discard is invisible, so `os.callback.received`
    /// reads as a crossing count when it is really twice that, and a callback that vanishes here
    /// cannot be told apart from the OS never delivering one.
    ///
    /// `.deliver` logs nothing: it is not a discard.
    func logDiscardedCallback(identifier: String, transition: GeofenceTransition, outcome: GeofenceMonitorEventOutcome) {
        guard let reason = outcome.diagnosticReason else { return }
        logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: reason)
    }

    /// An event CLMonitor delivered for a condition this process does not own.
    ///
    /// Logged, and logged as `info` rather than `os.callback.dropped`: the drop happens BEFORE
    /// `logReceivedCallback`, so there is no receipt for it to net against and filing it as a drop
    /// would inflate the received-vs-dropped count. Until now this path returned in silence, which
    /// makes "the OS never delivered it" and "we refused to look at it" the same empty capture —
    /// exactly the ambiguity a paired drive exists to resolve.
    func logUnownedEvent(_ event: CLMonitor.Event) {
        logger.geofenceInfo("callback_for_unowned_condition", fields: [
            ("id", event.identifier),
            ("state", String(describing: event.state))
        ])
    }

    /// The oldest queued event, discarded because the bootstrap has not bound `onTransition` and
    /// the queue is at its cap. Safe by design — CLMonitor re-emits current state — but it was
    /// invisible, so a lost crossing here looked identical to one that never arrived.
    func logOverflowedEvent(_ event: CLMonitor.Event) {
        logger.geofenceInfo("pending_event_overflow", fields: [("id", event.identifier)])
    }

    /// Internal (not private) only because it lives in a separate file from its callers.
    func currentLocationData() -> LocationData? {
        guard let location = bestKnownFix() else { return nil }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// Whether the device is inside the circle per the last known location; `nil` without a usable
    /// fix. No accuracy padding: a wrong guess costs one corrective event, absorbed by the baseline.
    func isDeviceInside(center: CLLocationCoordinate2D, radius: CLLocationDistance) -> Bool? {
        guard let location = bestKnownFix() else { return nil }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return location.distance(from: centerLocation) <= radius
    }
}
