import CioInternalCommon
import CoreLocation
import Foundation

/// Fields are optional so the backend can roll them out gradually; fallbacks live in `toDomain`.
struct GeofenceApiResponse: Decodable {
    let config: GeofenceApiConfig?
    /// Includes regions that failed to decode: `geofences` alone can't tell "sent none" from "none
    /// survived".
    let receivedRegionCount: Int
    let geofences: [GeofenceApiRegion]

    private enum CodingKeys: String, CodingKey {
        case config, geofences
    }

    /// Lenient per region: one malformed region must not cost the whole response.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.config = try container.decodeIfPresent(GeofenceApiConfig.self, forKey: .config)
        let lenient = try container.decodeIfPresent([LenientRegion].self, forKey: .geofences) ?? []
        self.receivedRegionCount = lenient.count
        self.geofences = lenient.compactMap(\.region)
    }

    init(config: GeofenceApiConfig?, geofences: [GeofenceApiRegion]) {
        self.config = config
        self.geofences = geofences
        self.receivedRegionCount = geofences.count
    }
}

private struct LenientRegion: Decodable {
    let region: GeofenceApiRegion?

    init(from decoder: Decoder) throws {
        self.region = try? GeofenceApiRegion(from: decoder)
    }
}

struct GeofenceApiConfig: Decodable {
    let localRefreshTriggerRadius: Double?
    let remoteFetchRefreshTriggerRadius: Double?
    /// Milliseconds.
    let remoteFetchRefreshExpiryTime: Double?
    /// Milliseconds.
    let duplicateEventsExpiryTime: Double?
    let maxMonitoringDistance: Double?
    let ios: GeofenceApiPlatformConfig?
}

struct GeofenceApiPlatformConfig: Decodable {
    let maxBusinessGeofence: Int?
}

struct GeofenceApiRegion: Decodable {
    let id: String
    let name: String?
    /// Absent means circle (v1). An unrecognized value drops the region, never falls back to the
    /// circle fields.
    let shape: String?
    let latitude: Double?
    let longitude: Double?
    let radius: Double?
    let geometry: GeofenceApiGeometry?
    let enclosingCircle: GeofenceApiEnclosingCircle?
    /// Present and non-null, decoded or not: both use `try?`, so a malformed value would otherwise
    /// look like a v1 circle.
    let carriesPolygonFields: Bool
    let externalId: String?
    let transitionTypes: [String]?
    /// Milliseconds since epoch.
    let lastUpdated: Double?
    let geosetIds: [String]?
    let metadata: [String: GeofenceMetadataValue]?
}

struct GeofenceApiGeometry: Decodable, Equatable {
    let type: String
    /// `[longitude, latitude]` positions: longitude FIRST, unlike the rest of the SDK. Exactly one
    /// ring; holes are unsupported.
    let coordinates: [[[Double]]]
}

struct GeofenceApiEnclosingCircle: Decodable, Equatable {
    let latitude: Double
    let longitude: Double
    /// Registered with the OS as-is.
    let baseRadiusM: Double
}

extension GeofenceApiRegion {
    private enum CodingKeys: String, CodingKey {
        case id, name, shape, latitude, longitude, radius, geometry, enclosingCircle, externalId,
             transitionTypes, lastUpdated, geosetIds, metadata
    }

    /// `id` and `geoset_ids` are `int64` on the wire but strings in some legacy payloads. In an
    /// extension so the memberwise init stays available to tests.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeStringOrInt(forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.shape = try container.decodeIfPresent(String.self, forKey: .shape)
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        self.radius = try container.decodeIfPresent(Double.self, forKey: .radius)
        self.geometry = try? container.decodeIfPresent(GeofenceApiGeometry.self, forKey: .geometry)
        self.enclosingCircle = try? container.decodeIfPresent(GeofenceApiEnclosingCircle.self, forKey: .enclosingCircle)
        self.carriesPolygonFields = container.holdsValue(forKey: .geometry) || container.holdsValue(forKey: .enclosingCircle)
        self.externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        self.transitionTypes = try container.decodeIfPresent([String].self, forKey: .transitionTypes)
        self.lastUpdated = try container.decodeIfPresent(Double.self, forKey: .lastUpdated)
        self.geosetIds = try container.decodeStringOrIntArrayIfPresent(forKey: .geosetIds)
        self.metadata = try container.decodeMetadataIfPresent(forKey: .metadata)
    }
}

private struct LenientMetadataValue: Decodable {
    let value: GeofenceMetadataValue?

    init(from decoder: Decoder) throws {
        self.value = try? GeofenceMetadataValue(from: decoder)
    }
}

/// `Int64`, not `Double`, keeps large ids exact.
private extension KeyedDecodingContainer {
    func decodeStringOrInt(forKey key: Key) throws -> String {
        if let int = try? decode(Int64.self, forKey: key) { return String(int) }
        return try decode(String.self, forKey: key)
    }

    /// Never fails the region: a non-object block is `nil` and non-scalar values are dropped.
    func decodeMetadataIfPresent(forKey key: Key) throws -> [String: GeofenceMetadataValue]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        guard let raw = try? decode([String: LenientMetadataValue].self, forKey: key) else { return nil }
        let filtered = raw.compactMapValues(\.value)
        return filtered.isEmpty ? nil : filtered
    }

    /// Present and non-null, whether or not the value decodes.
    func holdsValue(forKey key: Key) -> Bool {
        contains(key) && ((try? decodeNil(forKey: key)) == false)
    }

    func decodeStringOrIntArrayIfPresent(forKey key: Key) throws -> [String]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let ints = try? decode([Int64].self, forKey: key) { return ints.map(String.init) }
        return try decode([String].self, forKey: key)
    }
}

// MARK: - Domain mapping

extension GeofenceApiResponse {
    /// `nil` without a `config` block, so the cache save doesn't clobber a cached config.
    func toDomainConfig() -> GeofenceConfig? {
        config?.toDomain()
    }

    func toDomainRegions(onInvalidRegion: (String, GeofenceRegionDropReason) -> Void = { _, _ in }) -> [Geofence] {
        geofences.compactMap { region in
            switch region.toDomain() {
            case .success(let domain):
                return domain
            case .failure(let reason):
                onInvalidRegion(region.id, reason)
                return nil
            }
        }
    }
}

extension GeofenceApiConfig {
    /// Non-positive values fall back, out-of-range ones clamp. `maxBusinessGeofence` `0` is a valid
    /// kill switch.
    func toDomain() -> GeofenceConfig {
        let localRefresh = positive(localRefreshTriggerRadius)
            .map { $0.clamped(to: GeofenceConstants.minLocalRefreshRadius ... GeofenceConstants.maxLocalRefreshRadius) }
            ?? GeofenceConstants.movementTriggerRadius
        // Explicit `0` means no cap. Below the trigger radius falls back: a fence inside the trigger
        // but beyond the cap would never be re-ranked.
        let cap: Double
        switch maxMonitoringDistance {
        case .none:
            cap = GeofenceConstants.defaultMaxMonitoringDistance
        case .some(let value) where value == 0:
            cap = GeofenceConstants.noMonitoringDistanceCap
        case .some(let value) where value < localRefresh:
            cap = GeofenceConstants.defaultMaxMonitoringDistance
        case .some(let value):
            cap = value
        }
        return GeofenceConfig(
            localRefreshTriggerRadius: localRefresh,
            remoteFetchRefreshTriggerRadius: positive(remoteFetchRefreshTriggerRadius)
                ?? GeofenceConstants.serverFetchDistance,
            remoteFetchRefreshExpiry: positive(remoteFetchRefreshExpiryTime)
                .map { ($0 / 1000).clamped(to: GeofenceConstants.minRemoteFetchRefreshExpiry ... GeofenceConstants.maxRemoteFetchRefreshExpiry) }
                ?? GeofenceConstants.staleSyncInterval,
            duplicateEventsExpiry: positive(duplicateEventsExpiryTime)
                .map { ($0 / 1000).clamped(to: GeofenceConstants.minDuplicateEventsExpiry ... GeofenceConstants.maxDuplicateEventsExpiry) }
                ?? GeofenceConstants.eventCooldownInterval,
            maxBusinessGeofences: (ios?.maxBusinessGeofence).flatMap { value in
                (0 ... GeofenceConstants.maxMonitoredGeofences).contains(value) ? value : nil
            } ?? GeofenceConstants.maxMonitoredGeofences,
            maxMonitoringDistance: cap
        )
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension GeofenceApiRegion {
    func toDomain() -> Result<Geofence, GeofenceRegionDropReason> {
        let resolved: ResolvedGeometry?
        let dropReason: GeofenceRegionDropReason
        // Blank or padded is a slip, not a named shape: reaching `default`, which the all-dropped
        // guard exempts, would clear the cache.
        let named = shape?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch named?.isEmpty == true ? nil : named {
        case nil where carriesPolygonFields:
            // Keyed on the fields being PRESENT, not decoded: falling through to the circle fields
            // would monitor a shape the server never described.
            return .failure(.undescribedShape)
        case nil, "circle":
            resolved = resolvedCircle()
            dropReason = .unusableCircle
        case "polygon":
            resolved = resolvedPolygon()
            dropReason = .unusablePolygon
        default:
            return .failure(.unknownShape)
        }
        guard let resolved else { return .failure(dropReason) }
        return .success(Geofence(
            id: id,
            latitude: resolved.center.latitude,
            longitude: resolved.center.longitude,
            radius: resolved.radius,
            name: name.flatMap { $0.isEmpty ? nil : $0 },
            transitionTypes: Self.resolveTransitionTypes(transitionTypes),
            lastUpdated: lastUpdated.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(timeIntervalSince1970: 0),
            geosetIds: geosetIds ?? [],
            metadata: Self.cappedMetadata(metadata),
            vertices: resolved.vertices
        ))
    }

    private struct ResolvedGeometry {
        let center: LocationData
        let radius: Double
        let vertices: [LocationData]?
    }

    private func resolvedCircle() -> ResolvedGeometry? {
        guard let latitude, let longitude, let radius, radius > 0,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        else { return nil }
        return ResolvedGeometry(
            center: LocationData(latitude: latitude, longitude: longitude), radius: radius, vertices: nil
        )
    }

    private func resolvedPolygon() -> ResolvedGeometry? {
        guard let geometry, let enclosingCircle,
              geometry.type.caseInsensitiveCompare("Polygon") == .orderedSame,
              geometry.coordinates.count == 1,
              enclosingCircle.baseRadiusM > 0
        else { return nil }
        let center = CLLocationCoordinate2D(latitude: enclosingCircle.latitude, longitude: enclosingCircle.longitude)
        guard CLLocationCoordinate2DIsValid(center) else { return nil }
        guard let vertices = Self.polygonVertices(geometry.coordinates[0]) else { return nil }
        return ResolvedGeometry(
            center: LocationData(latitude: center.latitude, longitude: center.longitude),
            radius: enclosingCircle.baseRadiusM,
            vertices: vertices
        )
    }

    /// Validates once, here: the degeneracy checks are O(n²) and a region is rebuilt per wake.
    private static func polygonVertices(_ ring: [[Double]]) -> [LocationData]? {
        var positions: [LocationData] = []
        positions.reserveCapacity(ring.count)
        for position in ring {
            // GeoJSON positions are [longitude, latitude], plus an elevation we ignore.
            guard position.count >= 2 else { return nil }
            positions.append(LocationData(latitude: position[1], longitude: position[0]))
        }
        return PolygonRegion(validating: positions)?.vertices
    }

    private static func resolveTransitionTypes(_ raw: [String]?) -> Set<GeofenceTransition> {
        let defaults: Set<GeofenceTransition> = [.enter, .exit]
        guard let raw, !raw.isEmpty else { return defaults }
        let parsed = Set(raw.compactMap { GeofenceTransition(rawValue: $0.lowercased()) })
        return parsed.isEmpty ? defaults : parsed
    }

    /// Safety net for the short background wake. Per-value size is left to the server.
    private static func cappedMetadata(_ metadata: [String: GeofenceMetadataValue]?) -> [String: GeofenceMetadataValue] {
        guard let metadata, !metadata.isEmpty else { return [:] }
        var result: [String: GeofenceMetadataValue] = [:]
        var totalBytes = 0
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            guard result.count < GeofenceConstants.maxMetadataCount else { break }
            totalBytes += key.utf8.count + value.byteCount
            guard totalBytes <= GeofenceConstants.maxMetadataPayloadBytes else { break }
            result[key] = value
        }
        return result
    }
}

private extension GeofenceMetadataValue {
    var byteCount: Int {
        switch self {
        case .string(let value): return value.utf8.count
        case .int(let value): return String(value).utf8.count
        case .double(let value): return String(value).utf8.count
        case .bool(let value): return value ? 4 : 5
        }
    }
}
