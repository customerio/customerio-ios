@testable import CioLocation
import Foundation

/// Minimal mock for LocationProviding. Used only in Location tests to avoid CLLocationManager.
actor MockLocationProvider: LocationProviding {
    private var nextResult: LocationResult = .failure(.permissionDenied)

    private(set) var requestLocationCallCount = 0
    private(set) var cancelCallCount = 0

    func setResult(_ result: LocationResult) {
        nextResult = result
    }

    func requestLocationOnce() async -> LocationResult? {
        requestLocationCallCount += 1
        return nextResult
    }

    func cancel() async {
        cancelCallCount += 1
    }
}
