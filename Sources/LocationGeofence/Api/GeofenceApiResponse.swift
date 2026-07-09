import CioInternalCommon
import Foundation

/// Wire shape of the nearby geofence fetch response. Every field on `config` and per-region
/// `transitionTypes` / `lastUpdated` is optional so backend can roll fields out
/// gradually; per-field fallbacks live in `toDomain`.
struct GeofenceApiResponse: Decodable {
    let config: GeofenceApiConfig?
    let geofences: [GeofenceApiRegion]
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
    let latitude: Double
    let longitude: Double
    let radius: Double
    let externalId: String?
    let transitionTypes: [String]?
    /// Wire format is milliseconds since epoch.
    let lastUpdated: Double?
    /// IDs of the geosets this geofence belongs to; missing or empty means none.
    let geosetIds: [String]?
}

extension GeofenceApiRegion {
    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, radius, externalId, transitionTypes, lastUpdated, geosetIds
    }

    /// `id` and `geoset_ids` are `int64` on the wire but strings in some mocked/legacy payloads;
    /// both normalize to `String`. Declared in an extension so the memberwise init stays available
    /// to tests.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeStringOrInt(forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.radius = try container.decode(Double.self, forKey: .radius)
        self.externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        self.transitionTypes = try container.decodeIfPresent([String].self, forKey: .transitionTypes)
        self.lastUpdated = try container.decodeIfPresent(Double.self, forKey: .lastUpdated)
        self.geosetIds = try container.decodeStringOrIntArrayIfPresent(forKey: .geosetIds)
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

    func toDomainRegions() -> [Geofence] {
        geofences.map { $0.toDomain() }
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
    /// Empty / nil / all-unknown `transition_types` fall back to `[.enter, .exit]`; a mix of
    /// valid + unknown keeps just the valid subset. `lastUpdated` defaults to epoch when
    /// missing so callers can compare without unwrapping; `name` defaults to the empty string.
    func toDomain() -> Geofence {
        Geofence(
            id: id,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            name: name ?? "",
            transitionTypes: Self.resolveTransitionTypes(transitionTypes),
            lastUpdated: lastUpdated.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(timeIntervalSince1970: 0),
            geosetIds: geosetIds ?? []
        )
    }

    private static func resolveTransitionTypes(_ raw: [String]?) -> Set<GeofenceTransition> {
        let defaults: Set<GeofenceTransition> = [.enter, .exit]
        guard let raw, !raw.isEmpty else { return defaults }
        let parsed = Set(raw.compactMap { GeofenceTransition(rawValue: $0.lowercased()) })
        return parsed.isEmpty ? defaults : parsed
    }
}
