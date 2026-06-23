import CioInternalCommon
import CoreLocation
import Foundation

/// The `refresh` decision table, split out to keep the coordinator's core flow readable.
/// Methods are `internal` (not `private`) only because they live in a separate file from their
/// callers; they remain coordinator implementation detail.
extension GeofenceSyncCoordinatorImpl {
    /// Decision table for an identify / app-launch refresh, independent of what triggered it:
    /// re-fetch when the cache is stale in time, re-rank locally when the ranking is stale or the
    /// cache is unregistered, else skip.
    func refreshAction(location: LocationData, config: GeofenceConfig) async -> RefreshAction {
        let lastSync = await storage.getLastSync()
        // Measured from the last registration; nil (never set) → 0 → treated as within radius.
        let distanceFromLastRegistration = (await storage.getLastRegistrationCenter()).map { distance(from: $0, to: location) } ?? 0

        if isStaleInTime(lastSync: lastSync, config: config) { return .remote }
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

    /// Cache holds regions but nothing is registered with the OS (e.g. regs lost on sign-out) →
    /// re-register. A missing registration center is the "nothing registered" signal: it's set
    /// whenever the movement trigger registers and cleared on sign-out. A distance-capped set has
    /// no business regions but still registers the trigger (center set), so it's not "lost" — gating
    /// on the center too avoids a redundant re-rank on every refresh for a fully-capped workspace.
    func hasUnregisteredCache() async -> Bool {
        guard !(await storage.getCachedGeofences()).isEmpty else { return false }
        let noBusinessRegistered = await storage.getRegisteredBusinessIds().isEmpty
        let noRegistrationCenter = await storage.getLastRegistrationCenter() == nil
        return noBusinessRegistered && noRegistrationCenter
    }

    func distance(from: LocationData, to: LocationData) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
