import CioInternalCommon
import Foundation

/// Wire shape of `GET /geofences/nearby`. Every field on `config` and per-region
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
    let maxBusinessGeofences: Int?
}

struct GeofenceApiRegion: Decodable {
    let id: String
    let name: String?
    let latitude: Double
    let longitude: Double
    let radius: Double
    let externalId: String?
    let transitionTypes: [String]?
    /// Wire format is seconds since epoch.
    let lastUpdated: Double?
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
    /// clamp; `ios.maxBusinessGeofences` out of 0…19 falls back (`0` is a valid kill switch).
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
            maxBusinessGeofences: (ios?.maxBusinessGeofences).flatMap { value in
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
            lastUpdated: lastUpdated.map { Date(timeIntervalSince1970: $0) } ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func resolveTransitionTypes(_ raw: [String]?) -> Set<GeofenceTransition> {
        let defaults: Set<GeofenceTransition> = [.enter, .exit]
        guard let raw, !raw.isEmpty else { return defaults }
        let parsed = Set(raw.compactMap { GeofenceTransition(rawValue: $0.lowercased()) })
        return parsed.isEmpty ? defaults : parsed
    }
}
