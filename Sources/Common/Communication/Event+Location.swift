import Foundation

// MARK: - Location Data

/// Represents location data in a Codable, Sendable format.
///
/// This struct is used to pass location information between modules without
/// requiring CoreLocation imports in the Common module.
public struct LocationData: Codable, Sendable, Equatable {
    /// Latitude of the location in degrees.
    public let latitude: Double
    /// Longitude of the location in degrees.
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Event emitted when a location update should be tracked.
///
/// This event is published by the Location module and consumed by DataPipeline
/// to send location data to Customer.io servers.
public struct TrackLocationEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let timestamp: Date
    public let location: LocationData

    public init(
        storageId: String = UUID().uuidString,
        location: LocationData,
        timestamp: Date = Date(),
        params: [String: String] = [:]
    ) {
        self.storageId = storageId
        self.location = location
        self.timestamp = timestamp
        self.params = params
    }
}
