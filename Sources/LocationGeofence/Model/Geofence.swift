import CioInternalCommon
import Foundation

/// A geofence region returned by the server.
struct Geofence: Codable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    /// Radius in meters.
    let radius: Double
    let name: String
    let transitionTypes: Set<GeofenceTransition>
    let lastUpdated: Date
    /// IDs of the geosets this geofence belongs to. Empty when the geofence is
    /// in no geoset. Stamped onto transition events, one event per geoset.
    let geosetIds: [String]

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        name: String,
        transitionTypes: Set<GeofenceTransition>,
        lastUpdated: Date,
        geosetIds: [String] = []
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.name = name
        self.transitionTypes = transitionTypes
        self.lastUpdated = lastUpdated
        self.geosetIds = geosetIds
    }

    /// Custom decode so geofences cached to disk by SDK versions that predate
    /// `geosetIds` still decode (missing key means no geoset membership).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.radius = try container.decode(Double.self, forKey: .radius)
        self.name = try container.decode(String.self, forKey: .name)
        self.transitionTypes = try container.decode(Set<GeofenceTransition>.self, forKey: .transitionTypes)
        self.lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        self.geosetIds = try container.decodeIfPresent([String].self, forKey: .geosetIds) ?? []
    }
}
