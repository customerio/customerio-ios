import CioInternalCommon
import Foundation

/// The storage reads and writes `GeofenceSyncCoordinator` needs, and nothing else.
protocol GeofenceSyncStorage: Sendable {
    func getCachedConfig() async -> GeofenceConfig?
    func getCachedGeofences() async -> [Geofence]
    func getLastSync() async -> LastSyncRecord?
    func getLastRegistrationCenter() async -> LocationData?
    func getRegisteredBusinessIds() async -> Set<String>
    func setCachedGeofences(_ regions: [Geofence]) async
    func setCachedConfig(_ config: GeofenceConfig) async
    func recordSync(timestamp: Date, location: LocationData) async
    func recordRegistration(center: LocationData, businessIds: Set<String>) async
    func clearUserScopedState() async
}

extension GeofenceStorage: GeofenceSyncStorage {}
