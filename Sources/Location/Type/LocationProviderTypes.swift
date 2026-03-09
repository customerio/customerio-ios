import Foundation

// MARK: - AuthorizationSnapshot

/// Framework-agnostic authorization state for location. Used by currentAuthorizationStatus() and for pre-check before requesting location.
struct AuthorizationSnapshot: Equatable, Sendable {
    let status: AuthorizationStatus

    init(status: AuthorizationStatus) {
        self.status = status
    }

    /// Whether the app is authorized to use location (always or when in use).
    var isAuthorized: Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: true
        case .notDetermined, .restricted, .denied: false
        }
    }
}

/// Authorization status values (mirrors system behavior without Core Location dependency).
enum AuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorizedAlways
    case authorizedWhenInUse
}

// MARK: - LocationSnapshot

/// Framework-agnostic location details. Built from system location inside the provider.
struct LocationSnapshot: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let altitude: Double?

    init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double,
        altitude: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
    }
}

// MARK: - LocationProviderError

/// Reason location was not delivered. Returned from one-shot location request on failure.
enum LocationProviderError: Equatable, Sendable, Error {
    case permissionDenied
    case permissionNotDetermined
    case servicesDisabled
    case timeout
    case cancelled
}

// MARK: - LocationResult

/// Result of a one-shot location request. `nil` means the call was ignored (a request was already in flight).
enum LocationResult: Sendable {
    case success(LocationSnapshot)
    case failure(LocationProviderError)
}
