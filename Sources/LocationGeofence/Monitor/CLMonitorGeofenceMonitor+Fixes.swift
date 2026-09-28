import CioInternalCommon
import CoreLocation
import Foundation

/// Cached-fix reads and event diagnostics for the CLMonitor path.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor: GeofenceFixSelecting {
    /// Read through the authority seam so a replay can substitute it.
    var osCachedFix: CLLocation? { authManager.currentLocation }

    /// Records an OS-delivered crossing together with the fix the SDK will attach to it.
    func logReceivedCallback(identifier: String, transition: GeofenceTransition, eventDate: Date?) {
        let detail = bestKnownFixDetail()
        logger.geofenceCallbackReceived(
            identifier: identifier,
            transition: transition,
            fix: detail?.fix,
            source: detail?.source ?? .none,
            eventDate: eventDate,
            now: dateUtil.now
        )
    }

    /// Records a crossing the dedup baseline discarded, and why. CLMonitor can deliver a crossing
    /// twice, so without this `os.callback.received` overcounts and a discard looks like the OS
    /// never delivering.
    func logDiscardedCallback(identifier: String, transition: GeofenceTransition, outcome: GeofenceMonitorEventOutcome) {
        guard let reason = outcome.diagnosticReason else { return }
        logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: reason)
    }

    /// An event CLMonitor delivered for a condition this process does not own. Logged as `info`,
    /// not `os.callback.dropped`: it happens before `logReceivedCallback`, so there is no receipt
    /// to net it against.
    func logUnownedEvent(_ event: GeofenceConditionEvent) {
        logger.geofenceInfo("callback_for_unowned_condition", fields: [
            ("id", event.identifier),
            ("state", String(describing: event.state))
        ])
    }

    /// The oldest queued event, discarded because the bootstrap has not bound `onTransition` and
    /// the queue is at its cap.
    func logOverflowedEvent(_ event: GeofenceConditionEvent) {
        logger.geofenceInfo("pending_event_overflow", fields: [("id", event.identifier)])
    }

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
