@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("Location")
struct LocationSyncCoordinatorTests {
    private func makeCoordinator(
        dataPipeline: DataPipelineTrackingMock? = DataPipelineTrackingMock(),
        storage: LastLocationStorageImpl? = nil,
        dateUtil: DateUtilStub? = nil
    ) -> (LocationSyncCoordinator, LastLocationStorageImpl) {
        let store = storage ?? LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let util = dateUtil ?? DateUtilStub()
        let filter = LocationFilter(storage: store, dateUtil: util)
        let coordinator = LocationSyncCoordinator(
            storage: store,
            filter: filter,
            dataPipeline: dataPipeline,
            dateUtil: util,
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
    func processLocationUpdate_whenFilterAllowsAndPipelinePresent_callsTrack() async {
        let pipelineMock = DataPipelineTrackingMock()
        let (coordinator, storage) = makeCoordinator(dataPipeline: pipelineMock)
        await coordinator.processLocationUpdate(LocationData(latitude: 37.7749, longitude: -122.4194))
        #expect(pipelineMock.trackCallsCount == 1)
        #expect(pipelineMock.trackInvocations.first?.name == "CIO Location Update")
        #expect(pipelineMock.trackInvocations.first?.properties["latitude"] as? Double == 37.7749)
        #expect(pipelineMock.trackInvocations.first?.properties["longitude"] as? Double == -122.4194)
        let lastSynced = storage.getLastSynced()
        #expect(lastSynced?.location.latitude == 37.7749)
        #expect(lastSynced?.location.longitude == -122.4194)
    }

    @Test
    func processLocationUpdate_whenFilterDenies_doesNotCallTrack() async {
        let pipelineMock = DataPipelineTrackingMock()
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now
        let oldLocation = LocationData(latitude: 37.0, longitude: -122.0)
        storage.setCachedLocation(oldLocation)
        storage.recordLastSync(location: oldLocation, timestamp: now.addingTimeInterval(-3600)) // 1 hour ago
        let (coordinator, _) = makeCoordinator(
            dataPipeline: pipelineMock,
            storage: storage,
            dateUtil: dateUtil
        )
        await coordinator.processLocationUpdate(LocationData(latitude: 37.0001, longitude: -122.0001))
        #expect(pipelineMock.trackCallsCount == 0)
    }

    @Test
    func syncCachedLocationIfNeeded_whenHasCachedAndFilterAllows_callsTrack() async {
        let pipelineMock = DataPipelineTrackingMock()
        let (coordinator, storage) = makeCoordinator(dataPipeline: pipelineMock)
        storage.setCachedLocation(LocationData(latitude: 40.7128, longitude: -74.0060))
        await coordinator.syncCachedLocationIfNeeded()
        #expect(pipelineMock.trackCallsCount == 1)
        #expect(pipelineMock.trackInvocations.first?.properties["latitude"] as? Double == 40.7128)
        #expect(pipelineMock.trackInvocations.first?.properties["longitude"] as? Double == -74.0060)
        let lastSynced = storage.getLastSynced()
        #expect(lastSynced?.location.latitude == 40.7128)
    }

    @Test
    func syncCachedLocationIfNeeded_whenNoCachedLocation_doesNotCallTrack() async {
        let pipelineMock = DataPipelineTrackingMock()
        let (coordinator, _) = makeCoordinator(dataPipeline: pipelineMock)
        await coordinator.syncCachedLocationIfNeeded()
        #expect(pipelineMock.trackCallsCount == 0)
    }

    @Test
    func syncCachedLocationIfNeeded_whenFilterDenies_doesNotCallTrackNorRecordLastSync() async {
        let pipelineMock = DataPipelineTrackingMock()
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let dateUtil = DateUtilStub()
        let now = Date()
        dateUtil.givenNow = now
        let cachedLocation = LocationData(latitude: 37.0, longitude: -122.0)
        storage.setCachedLocation(cachedLocation)
        storage.recordLastSync(location: cachedLocation, timestamp: now.addingTimeInterval(-3600)) // 1 hour ago, same location → filter denies
        let (coordinator, _) = makeCoordinator(
            dataPipeline: pipelineMock,
            storage: storage,
            dateUtil: dateUtil
        )
        await coordinator.syncCachedLocationIfNeeded()
        #expect(pipelineMock.trackCallsCount == 0)
        let lastSynced = storage.getLastSynced()
        #expect(lastSynced != nil)
        #expect(lastSynced?.timestamp == now.addingTimeInterval(-3600)) // unchanged
    }

    @Test
    func processLocationUpdate_whenPipelineNil_doesNotCallTrack() async {
        let (coordinator, storage) = makeCoordinator(dataPipeline: nil)
        await coordinator.processLocationUpdate(LocationData(latitude: 37.7749, longitude: -122.4194))
        #expect(storage.getCachedLocation() != nil)
        #expect(storage.getLastSynced() == nil) // no pipeline → no track → no recordLastSync
    }

    @Test
    func processLocationUpdate_whenUserNotIdentified_doesNotCallTrack() async {
        let pipelineMock = DataPipelineTrackingMock(isUserIdentified: false)
        let (coordinator, storage) = makeCoordinator(dataPipeline: pipelineMock)
        await coordinator.processLocationUpdate(LocationData(latitude: 37.7749, longitude: -122.4194))
        #expect(pipelineMock.trackCallsCount == 0)
        #expect(storage.getLastSynced() == nil)
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
