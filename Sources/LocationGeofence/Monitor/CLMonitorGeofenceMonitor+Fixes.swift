import CioInternalCommon
import CoreLocation
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor: GeofenceFixSelecting {
    /// Read through the authority seam so a replay can substitute it.
    var osCachedFix: CLLocation? { authManager.currentLocation }

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

    func logDiscardedCallback(identifier: String, transition: GeofenceTransition, outcome: GeofenceMonitorEventOutcome) {
        guard let reason = outcome.diagnosticReason else { return }
        logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: reason)
    }

    /// `info`, not `os.callback.dropped`: no receipt was logged to net it against.
    func logUnownedEvent(_ event: GeofenceConditionEvent) {
        logger.geofenceInfo("callback_for_unowned_condition", fields: [
            ("id", event.identifier),
            ("state", String(describing: event.state))
        ])
    }

    func logOverflowedEvent(_ event: GeofenceConditionEvent) {
        logger.geofenceInfo("pending_event_overflow", fields: [("id", event.identifier)])
    }

    func currentLocationData() -> LocationData? {
        guard let location = bestKnownFix() else { return nil }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// No accuracy padding: a wrong guess costs one corrective event, absorbed by the baseline.
    func isDeviceInside(center: CLLocationCoordinate2D, radius: CLLocationDistance) -> Bool? {
        guard let location = bestKnownFix() else { return nil }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return location.distance(from: centerLocation) <= radius
    }
}
