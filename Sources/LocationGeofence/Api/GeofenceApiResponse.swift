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
    /// Per-field sanitization: non-positive numerics fall back to constants; `ios.maxBusinessGeofences`
    /// out of 0…19 falls back. `0` is preserved as a valid server-side kill switch.
    func toDomain() -> GeofenceConfig {
        GeofenceConfig(
            localRefreshTriggerRadius: positive(localRefreshTriggerRadius)
                ?? GeofenceConstants.movementTriggerRadius,
            remoteFetchRefreshTriggerRadius: positive(remoteFetchRefreshTriggerRadius)
                ?? GeofenceConstants.serverFetchDistance,
            remoteFetchRefreshExpiry: positive(remoteFetchRefreshExpiryTime).map { $0 / 1000 }
                ?? GeofenceConstants.staleSyncInterval,
            duplicateEventsExpiry: positive(duplicateEventsExpiryTime).map { $0 / 1000 }
                ?? GeofenceConstants.eventCooldownInterval,
            maxBusinessGeofences: (ios?.maxBusinessGeofences).flatMap { value in
                (0 ... GeofenceConstants.maxMonitoredGeofences).contains(value) ? value : nil
            } ?? GeofenceConstants.maxMonitoredGeofences
        )
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
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
