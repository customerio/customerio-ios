@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

@Suite("CoreLocationGeofenceMonitor.permissionTier")
struct GeofenceMonitorPermissionTierTests {
    @Test
    func permissionTier_givenAuthorizedAlways_expectBackgroundDelivery() {
        #expect(CoreLocationGeofenceMonitor.permissionTier(for: .authorizedAlways) == .backgroundDelivery)
    }

    @Test
    func permissionTier_givenAuthorizedWhenInUse_expectForegroundOnly() {
        #expect(CoreLocationGeofenceMonitor.permissionTier(for: .authorizedWhenInUse) == .foregroundOnly)
    }

    @Test
    func permissionTier_givenNotDetermined_expectBlocked() {
        #expect(CoreLocationGeofenceMonitor.permissionTier(for: .notDetermined) == .blocked)
    }

    @Test
    func permissionTier_givenDenied_expectBlocked() {
        #expect(CoreLocationGeofenceMonitor.permissionTier(for: .denied) == .blocked)
    }

    @Test
    func permissionTier_givenRestricted_expectBlocked() {
        #expect(CoreLocationGeofenceMonitor.permissionTier(for: .restricted) == .blocked)
    }
}
