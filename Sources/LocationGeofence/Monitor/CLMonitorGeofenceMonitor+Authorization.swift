import CioInternalCommon
import CoreLocation
import Foundation

/// Authorization handling for the CLMonitor path: the permission-tier log, the change handler,
/// and the iOS 18+ service session, split out to keep the monitor's event and lifecycle plumbing
/// readable (same convention as `+Registration`).
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func reportPermissionTier() {
        let status = authManager.authorizationStatus
        let tier = CoreLocationGeofenceMonitor.permissionTier(for: status)
        guard tier != lastLoggedPermissionTier else { return }
        lastLoggedPermissionTier = tier
        switch tier {
        case .blocked:
            logger.geofencePermissionUnavailable(currentStatus: status)
        case .foregroundOnly:
            logger.geofenceBackgroundDeliveryUnavailable(currentStatus: status)
        case .backgroundDelivery:
            logger.geofenceBackgroundDeliveryAvailable(currentStatus: status)
        }
    }

    // MARK: - Authorization

    /// Unfiltered: an improvement re-attempts registration, and a downgrade disarms visits.
    func handleAuthorizationChange() {
        updateServiceSession()
        onAuthorizationChanged?()
    }

    // MARK: - Service session (iOS 18+)

    /// Held only while Always is ALREADY granted: a session above the granted tier can prompt.
    func updateServiceSession() {
        authManager.updateServiceSession(isAlwaysAuthorized: authManager.authorizationStatus == .authorizedAlways)
    }
}
