@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("Location")
struct LocationSyncCoordinatorTests {
    private func makeCoordinator(
        eventBusHandler: EventBusHandlerMock = EventBusHandlerMock(),
        identificationState: IdentificationStateStub = IdentificationStateStub(isIdentified: true),
        storage: LastLocationStorageImpl? = nil,
        dateUtil: DateUtilStub? = nil
    ) -> (LocationSyncCoordinator, LastLocationStorageImpl) {
        let store = storage ?? LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
        let util = dateUtil ?? DateUtilStub()
        let filter = LocationFilter(storage: store, dateUtil: util)
        let coordinator = LocationSyncCoordinator(
            storage: store,
            filter: filter,
            eventBusHandler: eventBusHandler,
            identificationState: identificationState,
            dateUtil: util,
            logger: LoggerMock()
        )
        return (coordinator, store)
    }

    @Test
    func processLocationUpdate_alwaysUpdatesCache() async {
        let (coordinator, storage) = makeCoordinator(identificationState: IdentificationStateStub(isIdentified: false))
        let location = LocationData(latitude: 37.7749, longitude: -122.4194)
        await coordinator.processLocationUpdate(location)
        let cached = storage.getCachedLocation()
        #expect(cached?.latitude == 37.7749)
        #expect(cached?.longitude == -122.4194)
    }

    @Test
    func processLocationUpdate_whenNotIdentified_doesNotPostEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, _) = makeCoordinator(
            eventBusHandler: eventBusHandlerMock,
            identificationState: IdentificationStateStub(isIdentified: false)
        )
        await coordinator.processLocationUpdate(LocationData(latitude: 37.7749, longitude: -122.4194))
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func processLocationUpdate_whenIdentifiedAndFilterAllows_postsEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, _) = makeCoordinator(eventBusHandler: eventBusHandlerMock)
        await coordinator.processLocationUpdate(LocationData(latitude: 37.7749, longitude: -122.4194))
        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event?.location.latitude == 37.7749)
        #expect(event?.location.longitude == -122.4194)
    }

    @Test
    func processLocationUpdate_whenIdentifiedAndFilterDenies_doesNotPostEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let storage = LastLocationStorageImpl(storage: InMemorySharedKeyValueStorage())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now
        storage.setCachedLocation(LocationData(latitude: 37.0, longitude: -122.0))
        storage.recordLastSync(timestamp: now.addingTimeInterval(-3600)) // 1 hour ago
        let (coordinator, _) = makeCoordinator(
            eventBusHandler: eventBusHandlerMock,
            storage: storage,
            dateUtil: dateUtil
        )
        await coordinator.processLocationUpdate(LocationData(latitude: 37.0001, longitude: -122.0001))
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func syncCachedLocationIfNeeded_whenIdentifiedAndHasCached_postsEventAndRecordsLastSync() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, storage) = makeCoordinator(eventBusHandler: eventBusHandlerMock)
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        await coordinator.syncCachedLocationIfNeeded()
        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event?.location.latitude == 40.7128)
        #expect(event?.location.longitude == -74.0060)
        #expect(storage.getLastSynced() != nil)
    }

    @Test
    func syncCachedLocationIfNeeded_whenNotIdentified_doesNotPostEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, storage) = makeCoordinator(
            eventBusHandler: eventBusHandlerMock,
            identificationState: IdentificationStateStub(isIdentified: false)
        )
        storage.setCachedLocation(LocationData(latitude: 40.0, longitude: -74.0))
        await coordinator.syncCachedLocationIfNeeded()
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func syncCachedLocationIfNeeded_whenNoCachedLocation_doesNotPostEvent() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let (coordinator, _) = makeCoordinator(eventBusHandler: eventBusHandlerMock)
        await coordinator.syncCachedLocationIfNeeded()
        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func clearCache_clearsStorage() async {
        let (coordinator, storage) = makeCoordinator()
        storage.setCachedLocation(LocationData(latitude: 1, longitude: 2))
        storage.recordLastSync(timestamp: Date())
        await coordinator.clearCache()
        #expect(storage.getCachedLocation() == nil)
        #expect(storage.getLastSynced() == nil)
    }
}
