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
