import CioInternalCommon
import CoreLocation
import Foundation

extension GeofenceSyncCoordinatorImpl {
    func refreshAction(location: LocationData, config: GeofenceConfig) async -> RefreshAction {
        let lastSync = await storage.getLastSync()
        // No registration centre yet counts as within radius.
        let distanceFromLastRegistration = (await storage.getLastRegistrationCenter()).map { distance(from: $0, to: location) } ?? 0

        if isStaleInTime(lastSync: lastSync, config: config) { return .remote }
        if movedBeyondRefetchRadius(from: lastSync?.location, to: location, config: config) { return .remote }
        // Catches a movement-trigger EXIT missed while the app was dead.
        if distanceFromLastRegistration >= config.localRefreshTriggerRadius { return .local }
        if await hasUnregisteredCache() { return .local }
        return .skip
    }

    /// From the last registration centre, never the trigger: the trigger moves on every polygon
    /// wake, so re-ranking would never come due.
    func movedBeyondRerankRadius(to location: LocationData, config: GeofenceConfig) async -> Bool {
        guard let center = await storage.getLastRegistrationCenter() else { return true }
        return distance(from: center, to: location) >= config.localRefreshTriggerRadius
    }

    func movedBeyondRefetchRadius(from anchor: LocationData?, to location: LocationData, config: GeofenceConfig) -> Bool {
        guard let anchor else { return false }
        return distance(from: anchor, to: location) >= config.remoteFetchRefreshTriggerRadius
    }

    func isStaleInTime(lastSync: LastSyncRecord?, config: GeofenceConfig) -> Bool {
        guard let lastSync else { return true }
        return dateUtil.now.timeIntervalSince(lastSync.timestamp) >= config.remoteFetchRefreshExpiry
    }

    /// Also requires no registration centre: a fully distance-capped set registers no business
    /// regions but isn't lost, and would otherwise re-rank on every refresh.
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

    /// Before ranking, so a polygon the OS would refuse doesn't take a `maxBusinessGeofences` slot.
    @MainActor
    func monitorableRegions(_ regions: [Geofence]) -> [Geofence] {
        let maximumRadius = monitor.maximumMonitoringRadius
        return regions.filter { region in
            guard region.vertices != nil, region.radius > maximumRadius else { return true }
            logger.geofencePolygonExceedsMonitoringLimit(
                identifier: region.id, radius: region.radius, limit: maximumRadius
            )
            return false
        }
    }
}
