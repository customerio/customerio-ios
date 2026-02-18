import CioInternalCommon
import Foundation

/// Persists the latest cached location and the last-synced location + timestamp for the 24h + 1 km guardrails.
protocol LastLocationStorage: AnyObject {
    func getCachedLocation() -> LocationData?
    func setCachedLocation(_ location: LocationData)
    func getLastSynced() -> (location: LocationData, timestamp: Date)?
    /// Records that the current cached location was just synced at the given timestamp (avoids duplicating location in the API).
    func recordLastSync(timestamp: Date)
    func clearCache()
}

final class LastLocationStorageImpl: LastLocationStorage {
    private let storage: SharedKeyValueStorage

    init(storage: SharedKeyValueStorage) {
        self.storage = storage
    }

    func getCachedLocation() -> LocationData? {
        guard let lat = storage.double(.locationCachedLatitude),
              let lng = storage.double(.locationCachedLongitude)
        else {
            return nil
        }
        return LocationData(latitude: lat, longitude: lng)
    }

    func setCachedLocation(_ location: LocationData) {
        storage.setDouble(location.latitude, forKey: .locationCachedLatitude)
        storage.setDouble(location.longitude, forKey: .locationCachedLongitude)
    }

    func getLastSynced() -> (location: LocationData, timestamp: Date)? {
        guard let lat = storage.double(.locationLastSyncedLatitude),
              let lng = storage.double(.locationLastSyncedLongitude),
              let timestamp = storage.date(.locationLastSyncedTimestamp)
        else {
            return nil
        }
        return (LocationData(latitude: lat, longitude: lng), timestamp)
    }

    func recordLastSync(timestamp: Date) {
        guard let cached = getCachedLocation() else { return }
        storage.setDouble(cached.latitude, forKey: .locationLastSyncedLatitude)
        storage.setDouble(cached.longitude, forKey: .locationLastSyncedLongitude)
        storage.setDate(timestamp, forKey: .locationLastSyncedTimestamp)
    }

    func clearCache() {
        storage.setDouble(nil, forKey: .locationCachedLatitude)
        storage.setDouble(nil, forKey: .locationCachedLongitude)
        storage.setDouble(nil, forKey: .locationLastSyncedLatitude)
        storage.setDouble(nil, forKey: .locationLastSyncedLongitude)
        storage.setDate(nil, forKey: .locationLastSyncedTimestamp)
    }
}
