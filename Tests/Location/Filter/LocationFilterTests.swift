@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("Location")
struct LocationFilterTests {
    private func makeFilter(storage: LastLocationStorageImpl, dateUtil: DateUtilStub) -> LocationFilter {
        LocationFilter(storage: storage, dateUtil: dateUtil)
    }

    @Test
    func shouldSyncToServer_whenNoLastSynced_returnsTrue() {
        let storage = LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
        let dateUtil = DateUtilStub()
        let filter = makeFilter(storage: storage, dateUtil: dateUtil)
        let newLocation = LocationData(latitude: 37.7749, longitude: -122.4194)
        #expect(filter.shouldSyncToServer(newLocation: newLocation) == true)
    }

    @Test
    func shouldSyncToServer_whenLastSyncedLessThan24hAgo_returnsFalse() {
        let storage = LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now
        storage.setCachedLocation(LocationData(latitude: 37.0, longitude: -122.0))
        storage.recordLastSync(timestamp: now.addingTimeInterval(-3600)) // 1 hour ago
        let filter = makeFilter(storage: storage, dateUtil: dateUtil)
        let newLocation = LocationData(latitude: 37.7749, longitude: -122.4194)
        #expect(filter.shouldSyncToServer(newLocation: newLocation) == false)
    }

    @Test
    func shouldSyncToServer_whenLastSyncedLessThan1kmAway_returnsFalse() {
        let storage = LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now.addingTimeInterval(25 * 3600) // 25 hours later
        storage.setCachedLocation(LocationData(latitude: 37.7749, longitude: -122.4194))
        storage.recordLastSync(timestamp: now) // 25h ago
        let filter = makeFilter(storage: storage, dateUtil: dateUtil)
        // Same location (0 m away)
        let newLocation = LocationData(latitude: 37.7749, longitude: -122.4194)
        #expect(filter.shouldSyncToServer(newLocation: newLocation) == false)
    }

    @Test
    func shouldSyncToServer_whenLastSyncedAtLeast24hAgoAndAtLeast1kmAway_returnsTrue() {
        let storage = LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
        let dateUtil = DateUtilStub()
        let past = Date()
        dateUtil.givenNow = past.addingTimeInterval(25 * 3600) // 25 hours later
        storage.setCachedLocation(LocationData(latitude: 37.7749, longitude: -122.4194))
        storage.recordLastSync(timestamp: past)
        let filter = makeFilter(storage: storage, dateUtil: dateUtil)
        // ~14 km away (SF to Oakland area)
        let newLocation = LocationData(latitude: 37.8049, longitude: -122.2712)
        #expect(filter.shouldSyncToServer(newLocation: newLocation) == true)
    }
}
