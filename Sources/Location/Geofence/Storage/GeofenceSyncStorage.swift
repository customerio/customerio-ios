import CioInternalCommon
import Foundation

/// Narrow storage interface for `GeofenceSyncCoordinator`. Exposes only the reads and
/// writes the sync pipeline needs; cooldown methods stay on `GeofenceStorage` for
/// `GeofenceEventTracker`.
protocol GeofenceSyncStorage: Sendable {
    func getCachedConfig() async -> GeofenceConfig?
    func getCachedGeofences() async -> [Geofence]
    func getLastSync() async -> LastSyncRecord?
    func setCachedGeofences(_ regions: [Geofence]) async
    func setCachedConfig(_ config: GeofenceConfig) async
    func recordSync(timestamp: Date, location: LocationData) async
    func clearUserScopedState() async
}

extension GeofenceStorage: GeofenceSyncStorage {}
