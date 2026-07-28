@testable import CioLocation
import Foundation

/// Minimal mock for LocationProviding. Used only in Location tests to avoid CLLocationManager.
actor MockLocationProvider: LocationProviding {
    private var nextResult: LocationResult = .failure(.permissionDenied)

    private(set) var requestLocationCallCount = 0
    private(set) var cancelCallCount = 0

    private var isHolding = false
    private var holdContinuation: CheckedContinuation<Void, Never>?

    func setResult(_ result: LocationResult) {
        nextResult = result
    }

    /// The next `requestLocationOnce` suspends until `releaseHeldRequest()`, letting tests keep
    /// a request in flight while another arrives.
    func holdNextRequest() {
        isHolding = true
    }

    func releaseHeldRequest() {
        isHolding = false
        holdContinuation?.resume()
        holdContinuation = nil
    }

    func requestLocationOnce() async -> LocationResult? {
        requestLocationCallCount += 1
        if isHolding {
            await withCheckedContinuation { holdContinuation = $0 }
        }
        return nextResult
    }

    func cancel() async {
        cancelCallCount += 1
    }
}
