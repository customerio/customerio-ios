import CioInternalCommon
import Foundation

struct Geofence: Codable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    /// Meters.
    let radius: Double
    let name: String?
    let transitionTypes: Set<GeofenceTransition>
    let lastUpdated: Date
    let geosetIds: [String]
    let metadata: [String: GeofenceMetadataValue]
    /// `nil` for a circle. When set, `latitude`/`longitude`/`radius` are the covering circle registered
    /// at the OS; membership comes from the polygon, never the circle.
    let vertices: [LocationData]?

    init(
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        name: String?,
        transitionTypes: Set<GeofenceTransition>,
        lastUpdated: Date,
        geosetIds: [String] = [],
        metadata: [String: GeofenceMetadataValue] = [:],
        vertices: [LocationData]? = nil
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
        self.vertices = vertices
    }

    /// `nil` is EITHER a circle or a stored ring that no longer builds; check `vertices` for a circle.
    var polygonRegion: PolygonRegion? {
        vertices.flatMap(PolygonRegion.init(vertices:))
    }

    /// Tolerates missing `geosetIds` / `metadata` from caches written by older SDK versions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.radius = try container.decode(Double.self, forKey: .radius)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.transitionTypes = try container.decode(Set<GeofenceTransition>.self, forKey: .transitionTypes)
        self.lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        self.geosetIds = try container.decodeIfPresent([String].self, forKey: .geosetIds) ?? []
        self.metadata = try container.decodeIfPresent([String: GeofenceMetadataValue].self, forKey: .metadata) ?? [:]
        self.vertices = try container.decodeIfPresent([LocationData].self, forKey: .vertices)
    }
}
