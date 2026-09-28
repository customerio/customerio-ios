@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// `simulateVisit` returns the handler's disarm decision; this mock doesn't stop on `false`, so
/// `stopCallCount` can't see it.
@MainActor
final class MockGeofenceVisitMonitor: GeofenceVisitMonitoring {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var onVisit: GeofenceVisitHandler?
    /// With racing arms, only the last call shows the final state.
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
