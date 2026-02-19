import Foundation

/// Represents location data in a Codable, Sendable format.
///
/// This struct is used to pass location information between modules without
/// requiring CoreLocation imports in the Common module.
public struct LocationData: Codable, Sendable, Equatable {
    public let latitude: Double
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

/// Event posted by DataPipeline when a location update was actually tracked (user identified).
/// Carries the location that was tracked so the Location module can record it correctly (cache may have changed since the event was posted).
public struct LocationTrackedEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let location: LocationData
    public let timestamp: Date

    public init(
        storageId: String = UUID().uuidString,
        location: LocationData,
        timestamp: Date,
        params: [String: String] = [:]
    ) {
        self.storageId = storageId
        self.location = location
        self.timestamp = timestamp
        self.params = params
    }
}
