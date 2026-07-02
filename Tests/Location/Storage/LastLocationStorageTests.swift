@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("Location")
struct LastLocationStorageTests {
    private func makeStorage() -> LastLocationStorageImpl {
        LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
    }

    @Test
    func getCachedLocation_whenEmpty_returnsNil() {
        let storage = makeStorage()
        #expect(storage.getCachedLocation() == nil)
    }

    @Test
    func setCachedLocation_andGetCachedLocation_returnsSameLocation() {
        let storage = makeStorage()
        let location = LocationData(latitude: 37.7749, longitude: -122.4194)
        storage.setCachedLocation(location)
        let cached = storage.getCachedLocation()
        #expect(cached?.latitude == 37.7749)
        #expect(cached?.longitude == -122.4194)
    }

    @Test
    func getLastKnownLocation_whenNoInMemory_fallsBackToCached() {
        let storage = makeStorage()
        #expect(storage.getLastKnownLocation() == nil)
        storage.setCachedLocation(LocationData(latitude: 1, longitude: 2))
        let lastKnown = storage.getLastKnownLocation()
        #expect(lastKnown?.latitude == 1)
        #expect(lastKnown?.longitude == 2)
    }

    @Test
    func setLastKnownLocation_returnedByGetLastKnown_butNotPersistedAsCached() {
        let storage = makeStorage()
        storage.setLastKnownLocation(LocationData(latitude: 3, longitude: 4))
        // In-memory last-known is visible, but the persisted cache (enrichment source) is untouched.
        #expect(storage.getLastKnownLocation()?.latitude == 3)
        #expect(storage.getCachedLocation() == nil)
    }

    @Test
    func setLastKnownLocation_overridesCachedForLastKnownRead() {
        let storage = makeStorage()
        storage.setCachedLocation(LocationData(latitude: 1, longitude: 2))
        storage.setLastKnownLocation(LocationData(latitude: 3, longitude: 4))
        #expect(storage.getLastKnownLocation()?.latitude == 3)
        #expect(storage.getCachedLocation()?.latitude == 1)
    }

    @Test
    func clearCache_clearsInMemoryLastKnown() {
        let storage = makeStorage()
        storage.setLastKnownLocation(LocationData(latitude: 3, longitude: 4))
        storage.clearCache()
        #expect(storage.getLastKnownLocation() == nil)
    }

    @Test
    func getLastSynced_whenEmpty_returnsNil() {
        let storage = makeStorage()
        #expect(storage.getLastSynced() == nil)
    }

    @Test
    func recordLastSync_withExplicitLocation_persistsLastSynced() {
        let storage = makeStorage()
        let location = LocationData(latitude: 40.0, longitude: -74.0)
        let now = Date()
        storage.recordLastSync(location: location, timestamp: now)
        let lastSynced = storage.getLastSynced()
        #expect(lastSynced != nil)
        #expect(lastSynced?.location.latitude == 40.0)
        #expect(lastSynced?.location.longitude == -74.0)
        #expect(lastSynced?.timestamp == now)
    }

    @Test
    func clearCache_clearsCachedAndLastSynced() {
        let storage = makeStorage()
        let location = LocationData(latitude: 1, longitude: 2)
        storage.setCachedLocation(location)
        storage.recordLastSync(location: location, timestamp: Date())
        storage.clearCache()
        #expect(storage.getCachedLocation() == nil)
        #expect(storage.getLastSynced() == nil)
    }
}
