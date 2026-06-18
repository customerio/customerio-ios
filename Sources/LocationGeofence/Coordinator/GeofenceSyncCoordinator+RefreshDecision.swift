import CioInternalCommon
import CoreLocation
import Foundation

/// The `refresh` decision table, split out to keep the coordinator's core flow readable.
/// Methods are `internal` (not `private`) only because they live in a separate file from their
/// callers; they remain coordinator implementation detail.
extension GeofenceSyncCoordinatorImpl {
    /// Decision table for an identify / app-launch refresh, independent of what triggered it.
    /// Only the re-fetch question depends on the sync mode; time-staleness, ranking-staleness,
    /// and OS-registration gaps are mode-agnostic.
    func refreshAction(location: LocationData, config: GeofenceConfig) async -> RefreshAction {
        let lastSync = await storage.getLastSync()
        // Each distance is measured from its own reference: re-fetch from the last API fetch,
        // re-rank from the last registration. Nil (never set) → 0 → treated as within radius.
        let distanceFromLastFetch = lastSync.map { distance(from: $0.location, to: location) } ?? 0
        let distanceFromLastRegistration = (await storage.getLastRegistrationCenter()).map { distance(from: $0, to: location) } ?? 0

        if isStaleInTime(lastSync: lastSync, config: config) { return .remote }
        if syncMode.movementRequiresRemoteFetch(distanceFromAnchor: distanceFromLastFetch, config: config) {
            return .remote
        }
        // Device left the trigger radius since the nearest-set was last ranked — re-rank locally,
        // no network. This is the EXIT the live movement trigger fires on; refresh() catches one
        // missed while the app was dead (no boundary crossing to wake it).
        if distanceFromLastRegistration >= config.localRefreshTriggerRadius { return .local }
        if await hasUnregisteredCache() { return .local }
        return .skip
    }

    /// Cache aged out of its freshness window (or was never fetched).
    func isStaleInTime(lastSync: LastSyncRecord?, config: GeofenceConfig) -> Bool {
        guard let lastSync else { return true }
        return dateUtil.now.timeIntervalSince(lastSync.timestamp) >= config.remoteFetchRefreshExpiry
    }

    /// Cache holds regions but none are registered with the OS (e.g. regs lost on sign-out) → re-register.
    func hasUnregisteredCache() async -> Bool {
        guard !(await storage.getCachedGeofences()).isEmpty else { return false }
        return await storage.getRegisteredBusinessIds().isEmpty
    }

    func distance(from: LocationData, to: LocationData) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
