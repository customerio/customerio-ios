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

    func geofencePermissionUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registration skipped: location permission not granted (current status: \(currentStatus.rawValue)). The host app controls when and which permission to request.",
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registered for foreground delivery only: WhenInUse authorization granted (current status: \(currentStatus.rawValue)). Background transitions require Always authorization.",
            geofenceTag
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
