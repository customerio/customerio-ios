@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("Location")
struct LocationSyncCoordinatorTests {
    private func makeCoordinator(
        eventBusHandler: EventBusHandlerMock = EventBusHandlerMock(),
        storage: LastLocationStorageImpl? = nil,
        dateUtil: DateUtilStub? = nil
    ) -> (LocationSyncCoordinator, LastLocationStorageImpl) {
        let store = storage ?? LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let util = dateUtil ?? DateUtilStub()
        let filter = LocationFilter(storage: store, dateUtil: util)
        let coordinator = LocationSyncCoordinator(
            storage: store,
            filter: filter,
            eventBusHandler: eventBusHandler,
            logger: LoggerMock()
        )
        return (coordinator, store)
    }

    @Test
    func processLocationUpdate_alwaysUpdatesCache() async {
        let (coordinator, storage) = makeCoordinator()
        let location = LocationData(latitude: 37.7749, longitude: -122.4194)
        await coordinator.processLocationUpdate(location)
        let cached = storage.getCachedLocation()
        #expect(cached?.latitude == 37.7749)
        #expect(cached?.longitude == -122.4194)
    }

    @Test
    func processLocationUpdate_whenFilterAllows_postsEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, _) = makeCoordinator(eventBusHandler: eventBusHandlerMock)
        await coordinator.processLocationUpdate(LocationData(latitude: 37.7749, longitude: -122.4194))
        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event?.location.latitude == 37.7749)
        #expect(event?.location.longitude == -122.4194)
    }

    @Test
    func processLocationUpdate_whenFilterDenies_doesNotPostEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now
        let oldLocation = LocationData(latitude: 37.0, longitude: -122.0)
        storage.setCachedLocation(oldLocation)
        storage.recordLastSync(location: oldLocation, timestamp: now.addingTimeInterval(-3600)) // 1 hour ago
        let (coordinator, _) = makeCoordinator(
            eventBusHandler: eventBusHandlerMock,
            storage: storage,
            dateUtil: dateUtil
        )
        await coordinator.processLocationUpdate(LocationData(latitude: 37.0001, longitude: -122.0001))
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func syncCachedLocationIfNeeded_whenHasCachedAndFilterAllows_postsEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, storage) = makeCoordinator(eventBusHandler: eventBusHandlerMock)
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        await coordinator.syncCachedLocationIfNeeded()
        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event?.location.latitude == 40.7128)
        #expect(event?.location.longitude == -74.0060)
        // Last sync is recorded only when DataPipeline posts LocationTrackedEvent (after actual track).
    }

    @Test
    func recordLastSyncWhenTracked_recordsLocationAndTimestampInStorage() async {
        let (coordinator, storage) = makeCoordinator()
        let givenLocation = LocationData(latitude: 37.7749, longitude: -122.4194)
        let givenTimestamp = Date()
        await coordinator.recordLastSyncWhenTracked(location: givenLocation, timestamp: givenTimestamp)
        let lastSynced = storage.getLastSynced()
        #expect(lastSynced != nil)
        #expect(lastSynced?.location.latitude == givenLocation.latitude)
        #expect(lastSynced?.location.longitude == givenLocation.longitude)
        #expect(lastSynced?.timestamp == givenTimestamp)
    }

    @Test
    func syncCachedLocationIfNeeded_whenNoCachedLocation_doesNotPostEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, _) = makeCoordinator(eventBusHandler: eventBusHandlerMock)
        await coordinator.syncCachedLocationIfNeeded()
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func syncCachedLocationIfNeeded_whenFilterDenies_doesNotPostEventNorRecordLastSync() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now
        let cachedLocation = LocationData(latitude: 37.0, longitude: -122.0)
        storage.setCachedLocation(cachedLocation)
        storage.recordLastSync(location: cachedLocation, timestamp: now.addingTimeInterval(-3600)) // 1 hour ago, same location → filter denies
        let (coordinator, _) = makeCoordinator(
            eventBusHandler: eventBusHandlerMock,
            storage: storage,
            dateUtil: dateUtil
        )
        await coordinator.syncCachedLocationIfNeeded()
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
        let lastSynced = storage.getLastSynced()
        #expect(lastSynced != nil)
        #expect(lastSynced?.timestamp == now.addingTimeInterval(-3600)) // unchanged
    }

    @Test
    func clearCache_clearsStorage() async {
        let (coordinator, storage) = makeCoordinator()
        let location = LocationData(latitude: 1, longitude: 2)
        storage.setCachedLocation(location)
        storage.recordLastSync(location: location, timestamp: Date())
        await coordinator.clearCache()
        #expect(storage.getCachedLocation() == nil)
        #expect(storage.getLastSynced() == nil)
    }
}
