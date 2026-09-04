import CioInternalCommon
import CoreLocation
import Foundation

/// Wire shape of the nearby geofence fetch response. Every field on `config` and per-region
/// `transitionTypes` / `lastUpdated` is optional so backend can roll fields out
/// gradually; per-field fallbacks live in `toDomain`.
struct GeofenceApiResponse: Decodable {
    let config: GeofenceApiConfig?
    /// How many regions the payload carried, including any that failed to decode. `geofences`
    /// alone cannot tell "the server sent none" from "none of them survived".
    let receivedRegionCount: Int
    let geofences: [GeofenceApiRegion]

    private enum CodingKeys: String, CodingKey {
        case config, geofences
    }

    /// One malformed region must not cost the whole response, so regions are decoded leniently and
    /// the bad ones skipped.
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

/// Decodes a region without ever throwing, so one bad element cannot fail the array around it.
private struct LenientRegion: Decodable {
    let region: GeofenceApiRegion?

    init(from decoder: Decoder) throws {
        self.region = try? GeofenceApiRegion(from: decoder)
    }
}

/// Why a region on the wire never became a monitorable fence.
enum GeofenceRegionDropReason: String, Error {
    case unknownShape = "unrecognized or inconsistent shape"
    case unusableCircle = "invalid coordinates or radius"
    case unusablePolygon = "missing or undecodable polygon geometry"
}

struct GeofenceApiConfig: Decodable {
    let localRefreshTriggerRadius: Double?
    let remoteFetchRefreshTriggerRadius: Double?
    /// Wire format is milliseconds; converted to seconds in `toDomain`.
    let remoteFetchRefreshExpiryTime: Double?
    /// Wire format is milliseconds; converted to seconds in `toDomain`.
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
    /// `"circle"` or `"polygon"`; absent means circle, which is what v1 payloads look like. An
    /// unrecognized value drops the region — a shape we don't understand must never quietly fall
    /// back to whatever circle fields happen to be present.
    let shape: String?
    /// Circle geometry, present on a circle region. A polygon region carries `enclosingCircle`
    /// instead, so these are optional and their absence is resolved per shape rather than thrown.
    let latitude: Double?
    let longitude: Double?
    let radius: Double?
    /// GeoJSON boundary of a polygon region.
    let geometry: GeofenceApiGeometry?
    /// The circle the server guarantees contains the polygon — the shape actually registered at
    /// the OS as the wake trigger.
    let enclosingCircle: GeofenceApiEnclosingCircle?
    /// Whether the payload carried a non-null `geometry` or `enclosing_circle` at all, which is not
    /// the same as either having decoded: both use `try?`, so a malformed value becomes `nil` and
    /// would otherwise be indistinguishable from a v1 circle.
    var carriesPolygonFields: Bool = false
    let externalId: String?
    let transitionTypes: [String]?
    /// Wire format is milliseconds since epoch.
    let lastUpdated: Double?
    /// IDs of the geosets this geofence belongs to; missing or empty means none.
    let geosetIds: [String]?
    /// Workspace-defined metadata; missing or empty means none. Scalar values (string/number/bool)
    /// keep their type; null/array/object values are dropped during decode rather than failing the
    /// whole region.
    let metadata: [String: GeofenceMetadataValue]?
}

/// GeoJSON geometry of a polygon region. Decoded with `try?` at the region level, so a geometry we
/// can't read becomes `nil` and drops just this region instead of failing the whole response.
struct GeofenceApiGeometry: Decodable, Equatable {
    /// Must be `Polygon`. `MultiPolygon` and anything else drops the region.
    let type: String
    /// GeoJSON rings, each an array of `[longitude, latitude]` positions — longitude FIRST, which
    /// is the opposite of every other coordinate pair in this SDK. Ring 0 is the outer boundary and
    /// the contract guarantees exactly one; further rings would be holes, which we don't support.
    let coordinates: [[[Double]]]
}

/// The server-computed circle containing a polygon.
struct GeofenceApiEnclosingCircle: Decodable, Equatable {
    let latitude: Double
    let longitude: Double
    /// The smallest circle the server claims contains the polygon, registered with the OS as-is.
    let baseRadiusM: Double
}

extension GeofenceApiRegion {
    private enum CodingKeys: String, CodingKey {
        case id, name, shape, latitude, longitude, radius, geometry, enclosingCircle, externalId,
             transitionTypes, lastUpdated, geosetIds, metadata
    }

    /// `id` and `geoset_ids` are `int64` on the wire but strings in some mocked/legacy payloads;
    /// both normalize to `String`. Declared in an extension so the memberwise init stays available
    /// to tests.
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

/// A metadata value that never throws on decode: a scalar (string/number/bool) keeps its type, and
/// a null/array/object maps to `nil` so one bad entry doesn't fail the whole region. Used only at the
/// API boundary.
private struct LenientMetadataValue: Decodable {
    let value: GeofenceMetadataValue?

    init(from decoder: Decoder) throws {
        self.value = try? GeofenceMetadataValue(from: decoder)
    }
}

/// Decodes ids that arrive as JSON numbers or strings, normalized to `String`. `int64` is the wire
/// type so it's tried first, with `String` as the legacy/mocked fallback; `Int64` (not `Double`)
/// keeps large ids exact.
private extension KeyedDecodingContainer {
    func decodeStringOrInt(forKey key: Key) throws -> String {
        if let int = try? decode(Int64.self, forKey: key) { return String(int) }
        return try decode(String.self, forKey: key)
    }

    /// Metadata can never fail the region: a wrong-typed block (not an object) or absent/null/empty →
    /// nil, and non-scalar (array/object/null) values inside are dropped so a single bad value is
    /// skipped rather than failing decode; scalars keep their type.
    func decodeMetadataIfPresent(forKey key: Key) throws -> [String: GeofenceMetadataValue]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        guard let raw = try? decode([String: LenientMetadataValue].self, forKey: key) else { return nil }
        let filtered = raw.compactMapValues(\.value)
        return filtered.isEmpty ? nil : filtered
    }

    /// Whether the key is present with a non-null value, regardless of whether that value decodes
    /// into the type the field expects.
    func holdsValue(forKey key: Key) -> Bool {
        contains(key) && ((try? decodeNil(forKey: key)) == false)
    }

    /// Absent or null → nil, so a not-yet-rolled-out field is treated as "no value" rather than throwing.
    func decodeStringOrIntArrayIfPresent(forKey key: Key) throws -> [String]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let ints = try? decode([Int64].self, forKey: key) { return ints.map(String.init) }
        return try decode([String].self, forKey: key)
    }
}

// MARK: - Domain mapping

extension GeofenceApiResponse {
    /// Returns `nil` when backend didn't send a `config` block — gates the cache save so
    /// a missing block doesn't clobber a previously cached config.
    func toDomainConfig() -> GeofenceConfig? {
        config?.toDomain()
    }

    /// Regions the OS would reject (non-positive radius, out-of-range coordinates) are dropped
    /// here so one bad server region costs itself, not a nearest-selection slot or the whole sync.
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
    /// Coerces raw server values into sane bounds so a misconfigured backend can't push monitoring
    /// into a pathological state: non-positive values fall back; positive out-of-range radii/expiries
    /// clamp; `ios.maxBusinessGeofence` out of 0…19 falls back (`0` is a valid kill switch).
    func toDomain() -> GeofenceConfig {
        let localRefresh = positive(localRefreshTriggerRadius)
            .map { $0.clamped(to: GeofenceConstants.minLocalRefreshRadius ... GeofenceConstants.maxLocalRefreshRadius) }
            ?? GeofenceConstants.movementTriggerRadius
        // null → default cap (the field isn't sent today, and an unbounded default would register
        // far-away geofences a device can't reach soon); explicit `0` → no cap; a value below the
        // trigger radius (incl. negatives) would create a dead-zone — a geofence inside the trigger
        // but beyond the cap never gets re-ranked — so fall back to the default cap; else use it.
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
    /// `nil` when the region can't be registered as described: an unrecognized `shape`, a circle
    /// missing or misreporting its geometry, or a polygon whose ring or enclosing circle fails the
    /// acceptance rules below. Empty / nil / all-unknown `transition_types` fall back to
    /// `[.enter, .exit]`; a mix of valid + unknown keeps just the valid subset. `lastUpdated`
    /// defaults to epoch when missing so callers can compare without unwrapping. `name` is `nil`
    /// when the server omits it (or sends an empty string), so the domain value is always either
    /// `nil` or non-empty.
    func toDomain() -> Result<Geofence, GeofenceRegionDropReason> {
        let resolved: ResolvedGeometry?
        let dropReason: GeofenceRegionDropReason
        switch shape?.lowercased() {
        case nil where carriesPolygonFields:
            // Polygon fields with no discriminator: the payload describes something this decoder
            // cannot name. Falling through to the flat circle fields would monitor a shape the
            // server never described. Android drops the same combination. Keyed on the fields being
            // PRESENT, not on their having decoded — a malformed one is still a claim of a polygon.
            return .failure(.unknownShape)
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

    /// What the monitors need regardless of shape: the circle to register, plus the polygon that
    /// membership is decided against when there is one.
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

    /// Decodes the ring into the kernel's canonical (unclosed) vertices so the cache stores one
    /// representation. Validates here rather than at every use: the degeneracy checks are O(n²) and
    /// a region is rebuilt per wake and per evaluation, so this is the one place they can run once.
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

    /// Safety net so a runaway payload can't bloat a request in the short background wake: keeps
    /// entries (sorted by key for determinism) until either the count cap or the total key+value byte
    /// budget is hit. Per-value size is left to the server, which fully validates metadata.
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
    /// Serialized byte size for the payload budget: string UTF-8 length, or the numeric/bool text length.
    var byteCount: Int {
        switch self {
        case .string(let value): return value.utf8.count
        case .int(let value): return String(value).utf8.count
        case .double(let value): return String(value).utf8.count
        case .bool(let value): return value ? 4 : 5
        }
    }
}
