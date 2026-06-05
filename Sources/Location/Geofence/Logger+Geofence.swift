import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

extension Logger {
    func geofenceInvalidCoordinatesForRegion(_ identifier: String) {
        error(
            "Invalid coordinates for region \(identifier), skipping",
            geofenceTag,
            nil
        )
    }

    func geofenceMonitoringFailed(region: String, error: Error) {
        self.error(
            "Monitoring failed for region \(region)",
            geofenceTag,
            error
        )
    }

    func geofenceAlwaysAuthorizationRequired(currentStatus: CLAuthorizationStatus) {
        error(
            "Geofence monitoring requires 'Always' location authorization. Current status: \(currentStatus.rawValue). The host app must call CLLocationManager.requestAlwaysAuthorization().",
            geofenceTag,
            nil
        )
    }

    // MARK: - Event Tracking

    func geofenceEventTracked(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Tracked \(transition.rawValue) event for geofence \(geofenceId)",
            geofenceTag
        )
    }

    func geofenceEventSuppressed(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Suppressed duplicate \(transition.rawValue) event for geofence \(geofenceId), within cooldown",
            geofenceTag
        )
    }
}
