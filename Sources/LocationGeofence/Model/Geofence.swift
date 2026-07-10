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
    /// Workspace-defined key/value metadata; empty when the geofence carries none.
    /// Snapshotted onto transition events and preferred fresh from cache at send.
    let metadata: [String: GeofenceMetadataValue]

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        name: String,
        transitionTypes: Set<GeofenceTransition>,
        lastUpdated: Date,
        geosetIds: [String] = [],
        metadata: [String: GeofenceMetadataValue] = [:]
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.name = name
        self.transitionTypes = transitionTypes
        self.lastUpdated = lastUpdated
        self.geosetIds = geosetIds
        self.metadata = metadata
    }

    /// Custom decode so geofences cached by SDK versions predating `geosetIds` / `metadata` still
    /// decode (missing key means none). Disk values come from our own encoder, so strict decode is
    /// safe; the tolerant, null-dropping decode is at the API boundary in `GeofenceApiRegion`.
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
        self.metadata = try container.decodeIfPresent([String: GeofenceMetadataValue].self, forKey: .metadata) ?? [:]
    }
}
