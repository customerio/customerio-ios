@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("Location")
struct LastLocationStorageTests {
    private func makeStorage() -> LastLocationStorageImpl {
        LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
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
