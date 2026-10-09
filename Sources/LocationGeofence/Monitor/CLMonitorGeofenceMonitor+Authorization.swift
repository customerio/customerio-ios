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

    var locationAccess: GeofenceLocationAccess {
        GeofenceLocationAccess(status: authManager.authorizationStatus, fullAccuracy: authManager.isFullAccuracy)
    }

    // MARK: - Authorization

    /// Unfiltered: an improvement re-attempts registration, and a downgrade disarms visits.
    func handleAuthorizationChange() {
        updateServiceSession()
        interruptContinuityIfAccessDropped()
        onAuthorizationChanged?()
    }

    /// Losing Always or precise location means region events that would end a visit may no longer
    /// arrive. A repeated report, or an increase, changes nothing.
    private func interruptContinuityIfAccessDropped() {
        let access = locationAccess
        defer { lastObservedAccess = access }
        guard let previous = lastObservedAccess, access.isDowngrade(from: previous) else { return }
        onMonitoringInterrupted?(nil)
    }

    // MARK: - Service session (iOS 18+)

    /// Held only while Always is ALREADY granted: a session above the granted tier can prompt.
    func updateServiceSession() {
        authManager.updateServiceSession(isAlwaysAuthorized: authManager.authorizationStatus == .authorizedAlways)
    }
}
