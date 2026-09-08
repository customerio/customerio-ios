@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// Which registration generation an event belongs to. Tested through the pure selector rather than
/// the monitor: a real `CLMonitorGeofenceMonitor` builds a `CLLocationManager`, and instantiating
/// one in this suite crashed the test process outright.
@Suite("CLMonitor event circle generation")
struct CLMonitorEventCircleTests {
    @available(iOS 17.0, *)
    private func condition(longitude: Double, registeredAt: Date) -> CLMonitorGeofenceMonitor.RegisteredCondition {
        CLMonitorGeofenceMonitor.RegisteredCondition(
            center: LocationData(latitude: 0, longitude: longitude),
            radius: 300,
            transitionTypes: [.enter, .exit],
            registeredAt: registeredAt
        )
    }

    /// The case the signal exists for: the daemon raised the event against the old circle, and a
    /// refresh replaced the condition before the event stream handed it over.
    @Test
    func raisedAgainst_givenEventOlderThanTheCurrentRegistration_expectThePreviousGeneration() {
        guard #available(iOS 17.0, *) else { return }
        let replacedAt = Date()
        let selected = CLMonitorGeofenceMonitor.RegisteredCondition.raisedAgainst(
            current: condition(longitude: 0.005, registeredAt: replacedAt),
            previous: condition(longitude: 0, registeredAt: replacedAt.addingTimeInterval(-60)),
            raisedAt: replacedAt.addingTimeInterval(-1)
        )

        #expect(selected?.center.longitude == 0)
    }

    /// Control: an ordinary event postdates its registration and must resolve to the current
    /// circle, or every exit would be refused as stale.
    @Test
    func raisedAgainst_givenEventNewerThanTheCurrentRegistration_expectTheCurrentGeneration() {
        guard #available(iOS 17.0, *) else { return }
        let replacedAt = Date()
        let selected = CLMonitorGeofenceMonitor.RegisteredCondition.raisedAgainst(
            current: condition(longitude: 0.005, registeredAt: replacedAt),
            previous: condition(longitude: 0, registeredAt: replacedAt.addingTimeInterval(-60)),
            raisedAt: replacedAt.addingTimeInterval(1)
        )

        #expect(selected?.center.longitude == 0.005)
    }

    /// A cold wake holds no previous generation, so an older event cannot be attributed at all.
    @Test
    func raisedAgainst_givenNoPreviousGeneration_expectNil() {
        guard #available(iOS 17.0, *) else { return }
        let registeredAt = Date()
        let selected = CLMonitorGeofenceMonitor.RegisteredCondition.raisedAgainst(
            current: condition(longitude: 0.005, registeredAt: registeredAt),
            previous: nil,
            raisedAt: registeredAt.addingTimeInterval(-1)
        )

        #expect(selected == nil)
    }
}
