import CioInternalCommon
import CoreLocation
import Foundation

/// Encodes the 24h + 1 km guardrail: sync to server only if at least 24 hours since last sync and at least 1 km from last synced location.
/// Reads last-synced state and current time from its dependencies.
final class LocationFilter {
    // TODO: revert to 24h for production. 5 mins for testing.
    private static let minimumInterval: TimeInterval = 5 * 60 // 5 minutes (testing); production: 24 * 60 * 60
    private static let minimumDistanceMeters: CLLocationDistance = 1000 // 1 km

    private let storage: LastLocationStorage
    private let dateUtil: DateUtil

    init(storage: LastLocationStorage, dateUtil: DateUtil) {
        self.storage = storage
        self.dateUtil = dateUtil
    }

    /// Returns `true` if the backend should be updated with `newLocation`.
    /// No last synced → allow sync. Has last synced → allow only if (time since last sync ≥ 24h) and (distance from last synced to new ≥ 1 km).
    func shouldSyncToServer(newLocation: LocationData) -> Bool {
        let lastSynced = storage.getLastSynced()
        let now = dateUtil.now
        guard let last = lastSynced else { return true }
        let intervalOk = now.timeIntervalSince(last.timestamp) >= Self.minimumInterval
        let lastCLL = CLLocation(latitude: last.location.latitude, longitude: last.location.longitude)
        let newCLL = CLLocation(latitude: newLocation.latitude, longitude: newLocation.longitude)
        let distanceOk = lastCLL.distance(from: newCLL) >= Self.minimumDistanceMeters
        return intervalOk && distanceOk
    }
}
