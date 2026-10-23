@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

@Suite("CoreLocationGeofenceMonitor authorization")
@MainActor
struct CoreLocationMonitorAuthorizationTests {
    /// Losing Always or precise location ends the continuity a visit relies on; a repeated report
    /// or an increase does not.
    @Test
    func authorizationChange_givenDowngrade_expectContinuityInterruptedOncePerDrop() {
        let access = MonitorAccessBox(GeofenceLocationAccess(delivery: .background, fullAccuracy: true))
        let monitor = CoreLocationGeofenceMonitor(
            logger: LoggerMock(), dateUtil: DateUtilStub(), readLocationAccess: { _ in access.value }
        )
        var interruptions: [String?] = []
        monitor.setOnMonitoringInterrupted { interruptions.append($0) }

        monitor.locationManagerDidChangeAuthorization(monitor.manager)
        access.value = GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true)
        monitor.locationManagerDidChangeAuthorization(monitor.manager)
        monitor.locationManagerDidChangeAuthorization(monitor.manager)
        access.value = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
        monitor.locationManagerDidChangeAuthorization(monitor.manager)
        access.value = GeofenceLocationAccess(delivery: .background, fullAccuracy: false)
        monitor.locationManagerDidChangeAuthorization(monitor.manager)

        #expect(interruptions == [nil, nil])
    }

    /// The authorization handler still re-runs setup on every change, downgrade or not.
    @Test
    func authorizationChange_givenDowngrade_expectSetupStillRerun() {
        let access = MonitorAccessBox(GeofenceLocationAccess(delivery: .background, fullAccuracy: true))
        let monitor = CoreLocationGeofenceMonitor(
            logger: LoggerMock(), dateUtil: DateUtilStub(), readLocationAccess: { _ in access.value }
        )
        var reruns = 0
        monitor.setOnAuthorizationChanged { reruns += 1 }

        access.value = GeofenceLocationAccess(delivery: .none, fullAccuracy: true)
        monitor.locationManagerDidChangeAuthorization(monitor.manager)

        #expect(reruns == 1)
    }
}

@MainActor
private final class MonitorAccessBox {
    var value: GeofenceLocationAccess

    init(_ value: GeofenceLocationAccess) {
        self.value = value
    }
}
