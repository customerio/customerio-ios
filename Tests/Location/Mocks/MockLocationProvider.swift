@testable import CioLocation
import Foundation

/// Minimal mock for LocationProviding. Used only in Location tests to avoid CLLocationManager.
actor MockLocationProvider: LocationProviding {
    private var authStatus = AuthorizationSnapshot(status: .denied)
    private var requestLocationResult: Result<LocationSnapshot, Error> = .failure(LocationProviderError.permissionDenied)

    private(set) var requestLocationCallCount = 0
    private(set) var cancelRequestLocationCallCount = 0
    private(set) var currentAuthorizationStatusCallCount = 0

    func setAuthStatus(_ status: AuthorizationStatus) {
        authStatus = AuthorizationSnapshot(status: status)
    }

    func setRequestLocationResult(_ result: Result<LocationSnapshot, Error>) {
        requestLocationResult = result
    }

    func currentAuthorizationStatus() async -> AuthorizationSnapshot {
        currentAuthorizationStatusCallCount += 1
        return authStatus
    }

    func cancelRequestLocation() async {
        cancelRequestLocationCallCount += 1
    }

    func requestLocation(granularity: LocationGranularity) async throws -> LocationSnapshot {
        requestLocationCallCount += 1
        switch requestLocationResult {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        }
    }
}
