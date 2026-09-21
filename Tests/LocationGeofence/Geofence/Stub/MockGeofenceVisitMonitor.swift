@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Lets a test drive the visit wake without a `CLLocationManager`.
///
/// `simulateVisit` returns what the bound handler answered, because that answer is not just a
/// side effect — it is the disarm decision, and a test asserting only on `stopCallCount` would
/// pass against a handler that returned the wrong value and never got asked.
@MainActor
final class MockGeofenceVisitMonitor: GeofenceVisitMonitoring {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var onVisit: GeofenceVisitHandler?

    func setOnVisit(_ handler: GeofenceVisitHandler?) {
        onVisit = handler
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    @discardableResult
    func simulateVisit(
        latitude: Double = 37.0,
        longitude: Double = -122.0,
        horizontalAccuracy: Double = 30,
        isArrival: Bool = true
    ) -> Bool? {
        onVisit?(
            GeofenceVisit(
                coordinate: LocationData(latitude: latitude, longitude: longitude),
                horizontalAccuracy: horizontalAccuracy,
                arrivalDate: Date(),
                departureDate: isArrival ? .distantFuture : Date()
            )
        )
    }
}
