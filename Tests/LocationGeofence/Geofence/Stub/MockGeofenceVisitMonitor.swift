@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Lets a test drive the visit wake without a `CLLocationManager`.
///
/// `simulateVisit` returns the handler's answer because that answer is the disarm decision; this
/// mock does not stop on `false`, so `stopCallCount` alone cannot see it.
@MainActor
final class MockGeofenceVisitMonitor: GeofenceVisitMonitoring {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var onVisit: GeofenceVisitHandler?
    /// Call order, not just counts: two racing arms can each land once, so only the last call
    /// says which state the monitor was left in.
    private(set) var calls: [Call] = []

    enum Call: Equatable {
        case start
        case stop
    }

    func setOnVisit(_ handler: GeofenceVisitHandler?) {
        onVisit = handler
    }

    func start() {
        startCallCount += 1
        calls.append(.start)
    }

    func stop() {
        stopCallCount += 1
        calls.append(.stop)
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
