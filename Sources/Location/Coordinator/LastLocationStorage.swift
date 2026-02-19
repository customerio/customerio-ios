import CioInternalCommon
import Foundation

/// Persists the latest cached location and the last-synced location + timestamp for the 24h + 1 km guardrails.
protocol LastLocationStorage: AnyObject {
    func getCachedLocation() -> LocationData?
    func setCachedLocation(_ location: LocationData)
    func getLastSynced() -> (location: LocationData, timestamp: Date)?
    /// Records that the given location was synced at the given timestamp. Uses explicit location so the correct one is stored even if cache was overwritten before the ack arrived.
    func recordLastSync(location: LocationData, timestamp: Date)
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

    func recordLastSync(location: LocationData, timestamp: Date) {
        storage.setDouble(location.latitude, forKey: .locationLastSyncedLatitude)
        storage.setDouble(location.longitude, forKey: .locationLastSyncedLongitude)
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
