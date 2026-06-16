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

/// Posted whenever the Location module finishes processing a fresh location fix
/// (the fix has been cached and evaluated for sync). Observed by the geofence wiring
/// to re-arm its first-run refresh after a fix arrives following an earlier
/// "no cached location" skip. Routing this through the EventBus keeps geofence
/// decoupled from `LocationSyncCoordinator`'s internals.
public struct LocationAcquiredEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let location: LocationData
    public let timestamp: Date

    /// Not persisted: a location fix is only useful in the moment, so it is dropped when unobserved
    /// rather than written to disk for replay.
    public var isPersistent: Bool { false }

    public init(storageId: String = UUID().uuidString, location: LocationData, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.location = location
        self.timestamp = timestamp
        self.params = params
    }
}
