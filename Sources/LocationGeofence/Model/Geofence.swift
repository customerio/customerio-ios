import CioInternalCommon
import Foundation

enum GeofenceDwellLimits {
    /// Shared with Android: GMS represents loitering delay as signed 32-bit milliseconds.
    static let maxThresholdSeconds = Int(Int32.max) / 1000
}

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
    /// Seconds required inside for one dwell event per visit. Zero disables dwell.
    let dwellThresholdSeconds: Int

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
        vertices: [LocationData]? = nil,
        dwellThresholdSeconds: Int = 0
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
        self.dwellThresholdSeconds = dwellThresholdSeconds
    }

    /// `nil` is EITHER a circle or a stored ring that no longer builds; check `vertices` for a circle.
    var polygonRegion: PolygonRegion? {
        vertices.flatMap(PolygonRegion.init(vertices:))
    }

    /// The edges registered with the OS. A circle that tracks a visit needs both — ENTER starts the
    /// visit, EXIT ends it — whatever the customer configured. A polygon's covering circle is
    /// machinery and always reports both, so membership can advance; its filter applies to the
    /// verdict instead.
    var osTransitionTypes: Set<GeofenceTransition> {
        guard vertices == nil else { return [.enter, .exit] }
        return dwellThresholdSeconds > 0
            ? [.enter, .exit]
            : transitionTypes.intersection([.enter, .exit])
    }

    /// A circle's OS edges registered only for visit bookkeeping, which the customer never
    /// configured and must never receive. Empty for a polygon, whose OS edges are never its events.
    var unconfiguredOsTransitions: Set<GeofenceTransition> {
        guard vertices == nil else { return [] }
        return osTransitionTypes.subtracting(transitionTypes)
    }

    /// What a visit is measured against: the shape and the threshold, nothing else. `lastUpdated`
    /// is deliberately left out — the backend bumps it for a name, metadata or geoset edit too, and
    /// a refresh carrying one must not end a live visit. Matches Android's `transitionRevision`.
    var dwellRevision: String {
        let ring = vertices?.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";") ?? "circle"
        return "\(id)|\(latitude)|\(longitude)|\(radius)|\(ring)|\(dwellThresholdSeconds)"
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
        self.dwellThresholdSeconds = try container.decodeIfPresent(Int.self, forKey: .dwellThresholdSeconds) ?? 0
    }
}
