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

/// Serializes all access to the state store so that load→modify→save is atomic and concurrent callers cannot overwrite each other's updates.
final class LastLocationStorageImpl: LastLocationStorage {
    private let lock = NSLock()
    private let stateStore: LastLocationStateStore

    init(stateStore: LastLocationStateStore) {
        self.stateStore = stateStore
    }

    func getCachedLocation() -> LocationData? {
        lock.lock()
        defer { lock.unlock() }
        return stateStore.load()?.cachedLocation
    }

    func setCachedLocation(_ location: LocationData) {
        lock.lock()
        defer { lock.unlock() }
        var state = stateStore.load() ?? LastLocationState()
        state.cachedLocation = location
        stateStore.save(state)
    }

    func getLastSynced() -> (location: LocationData, timestamp: Date)? {
        lock.lock()
        defer { lock.unlock() }
        guard let record = stateStore.load()?.lastSynced else { return nil }
        return (record.location, record.timestamp)
    }

    func recordLastSync(location: LocationData, timestamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        var state = stateStore.load() ?? LastLocationState()
        state.lastSynced = LastSyncedRecord(location: location, timestamp: timestamp)
        stateStore.save(state)
    }

    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        stateStore.clear()
    }
}
