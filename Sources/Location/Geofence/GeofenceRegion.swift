import Foundation

/// Represents a geographic region to monitor for geofencing events.
public struct GeofenceRegion: Codable, Equatable, Sendable {
    /// Unique identifier for the geofence
    public let id: String

    /// Center latitude of the geofence (must be in range [-90, 90])
    public let latitude: Double

    /// Center longitude of the geofence (must be in range [-180, 180])
    public let longitude: Double

    /// Radius in meters (default: 100.0)
    public let radius: Double

    /// Optional human-readable name
    public let name: String?

    /// Optional app-provided metadata to include in events
    public let customData: [String: String]?

    /// Optional dwell time in milliseconds (default: 10 minutes)
    public let dwellTimeMs: Int64?

    /// Creates a new geofence region with validation.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the geofence
    ///   - latitude: Center latitude (must be in range [-90, 90])
    ///   - longitude: Center longitude (must be in range [-180, 180])
    ///   - radius: Radius in meters (default: 100.0)
    ///   - name: Optional human-readable name
    ///   - customData: Optional app-provided metadata
    ///   - dwellTimeMs: Optional dwell time in milliseconds (default: 10 minutes)
    /// - Throws: `GeofenceValidationError` if coordinates are invalid
    public init(
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Double = GeofenceConstants.DEFAULT_RADIUS_METERS,
        name: String? = nil,
        customData: [String: String]? = nil,
        dwellTimeMs: Int64? = nil
    ) throws {
        guard latitude >= -90.0, latitude <= 90.0 else {
            throw GeofenceValidationError.invalidLatitude(latitude)
        }

        guard longitude >= -180.0, longitude <= 180.0 else {
            throw GeofenceValidationError.invalidLongitude(longitude)
        }

        guard radius > 0 else {
            throw GeofenceValidationError.invalidRadius(radius)
        }

        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.name = name
        self.customData = customData
        self.dwellTimeMs = dwellTimeMs
    }

    /// Returns the effective dwell time, using the default if not specified
    var effectiveDwellTimeMs: Int64 {
        dwellTimeMs ?? GeofenceConstants.DEFAULT_DWELL_TIME_MS
    }
}

/// Errors that can occur during geofence validation
public enum GeofenceValidationError: Error, LocalizedError {
    case invalidLatitude(Double)
    case invalidLongitude(Double)
    case invalidRadius(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidLatitude(let value):
            return "Invalid latitude: \(value). Must be in range [-90, 90]"
        case .invalidLongitude(let value):
            return "Invalid longitude: \(value). Must be in range [-180, 180]"
        case .invalidRadius(let value):
            return "Invalid radius: \(value). Must be greater than 0"
        }
    }
}
