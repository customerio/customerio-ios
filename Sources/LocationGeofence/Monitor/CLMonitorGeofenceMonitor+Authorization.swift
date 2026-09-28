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

    /// Fires once when the delegate is set (harmless) and again on every change, keeping the service
    /// session in step with the granted tier. Surfaced UNFILTERED in BOTH directions: an improvement
    /// lets the bootstrap re-attempt registration, and a downgrade is what disarms visit monitoring.
    /// Internal (not private) only because the monitor's `init` wires it from the main file.
    func handleAuthorizationChange() {
        updateServiceSession()
        onAuthorizationChanged?()
    }

    // MARK: - Service session (iOS 18+)

    /// On iOS 18+, `CLMonitor.events` stops yielding in the background unless a `CLServiceSession`
    /// asserts continued interest — Always authorization alone no longer suffices. Held for the
    /// monitor's lifetime, but only while Always is ALREADY granted: a session above the granted
    /// tier can put up a permission prompt, and prompting is the host's decision, never the SDK's.
    /// Internal (not private) only because the monitor's `init` calls it from the main file.
    func updateServiceSession() {
        authManager.updateServiceSession(isAlwaysAuthorized: authManager.authorizationStatus == .authorizedAlways)
    }
}
