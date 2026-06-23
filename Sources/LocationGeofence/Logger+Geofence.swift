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

    // MARK: - Sync

    func geofenceSyncSkipped(reason: String) {
        debug("Sync skipped: \(reason)", geofenceTag)
    }

    func geofenceSyncSkippedFresh() {
        debug("Sync skipped: last server fetch is within freshness window", geofenceTag)
    }

    func geofenceSyncFetchFailed(error: GeofenceApiError) {
        self.error("Sync fetch failed: \(error)", geofenceTag, nil)
    }

    func geofenceSyncCompleted(registeredCount: Int) {
        info("Sync completed: registered \(registeredCount) business geofences + 1 movement trigger", geofenceTag)
    }

    func geofenceMovementTrigger(tier: HandleMovementTier) {
        debug("Movement trigger EXIT: \(tier.rawValue)", geofenceTag)
    }

    func geofenceSyncSupersededByUserChange() {
        info("Sync result discarded: identified user changed during fetch", geofenceTag)
    }

    func geofenceResetCompleted() {
        info("Reset completed: monitoring stopped and user-scoped state cleared", geofenceTag)
    }

    func geofenceResetSuperseded() {
        debug("Reset skipped: another user is signed in", geofenceTag)
    }

    func geofenceFirstRunRearm() {
        debug("First-run refresh re-armed by new location fix", geofenceTag)
    }

    func geofenceRegionsAdopted(count: Int) {
        debug("Adopted \(count) OS-persisted region(s) on launch; skipping re-registration", geofenceTag)
    }
}
