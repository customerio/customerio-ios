@testable import CioInternalCommon
@testable import CioLocation
import CoreLocation
import SharedTests
import Testing

@Suite("Location")
struct LocationServicesImplementationTests {
    private func makeCoordinator(dataPipeline: DataPipelineTrackingMock? = DataPipelineTrackingMock()) -> LocationSyncCoordinator {
        let storage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        let dateUtil = DateUtilStub()
        let filter = LocationFilter(storage: storage, dateUtil: dateUtil)
        return LocationSyncCoordinator(
            storage: storage,
            filter: filter,
            dataPipeline: dataPipeline,
            dateUtil: dateUtil,
            logger: LoggerMock()
        )
    }

    private func makeImplementation(
        mode: LocationTrackingMode = .manual,
        dataPipeline: DataPipelineTrackingMock? = DataPipelineTrackingMock(),
        logger: LoggerMock = LoggerMock(),
        locationProvider: MockLocationProvider = MockLocationProvider(),
        lifecycleNotifying: AppLifecycleNotifying = NoOpAppLifecycleNotifying(),
        applicationStateProvider: ApplicationStateProvider = StubApplicationStateProvider()
    ) -> LocationServicesImplementation {
        let config = LocationConfig(mode: mode)
        let coordinator = makeCoordinator(dataPipeline: dataPipeline)
        return LocationServicesImplementation(
            config: config,
            logger: logger,
            locationProvider: locationProvider,
            locationSyncCoordinator: coordinator,
            lifecycleNotifying: lifecycleNotifying,
            applicationStateProvider: applicationStateProvider
        )
    }

    /// Yields so the fire-and-forget task from requestLocationUpdate() can run (no sleep).
    private func yieldForLocationTask() async {
        for _ in 0 ..< 40 {
            await Task.yield()
        }
    }

    @Test
    func setLastKnownLocation_givenTrackingDisabled_expectNoTrackCalled() async {
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(mode: .off, dataPipeline: pipelineMock)
        let validLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        service.setLastKnownLocation(validLocation)
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 0)
    }

    @Test
    func setLastKnownLocation_givenInvalidCoordinates_expectNoTrackCalled() async {
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(dataPipeline: pipelineMock)
        let invalidLocation = CLLocation(latitude: 91.0, longitude: 181.0)

        service.setLastKnownLocation(invalidLocation)
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 0)
    }

    @Test
    func setLastKnownLocation_givenValidLocation_expectTrackCalledWithCorrectData() async {
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(dataPipeline: pipelineMock)
        let expectedLatitude = 37.7749
        let expectedLongitude = -122.4194
        let validLocation = CLLocation(latitude: expectedLatitude, longitude: expectedLongitude)

        service.setLastKnownLocation(validLocation)
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 1)
        #expect(pipelineMock.trackInvocations.first?.name == "CIO Location Update")
        #expect(pipelineMock.trackInvocations.first?.properties["latitude"] as? Double == expectedLatitude)
        #expect(pipelineMock.trackInvocations.first?.properties["longitude"] as? Double == expectedLongitude)
    }

    @Test
    func setLastKnownLocation_givenMultipleCalls_expectOnlyFirstTrackedDueToFilter() async {
        // Coordinator records last sync synchronously after each track. Second location is within 24h of first,
        // so the 24h + 1 km filter correctly allows only the first and denies the second.
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(dataPipeline: pipelineMock)
        let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let location2 = CLLocation(latitude: 40.7128, longitude: -74.0060)

        service.setLastKnownLocation(location1)
        service.setLastKnownLocation(location2)
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 1)
        #expect(pipelineMock.trackInvocations.first?.properties["latitude"] as? Double == 37.7749)
        #expect(pipelineMock.trackInvocations.first?.properties["longitude"] as? Double == -122.4194)
    }

    @Test
    func setLastKnownLocation_givenZeroCoordinates_expectTrackCalled() async {
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(dataPipeline: pipelineMock)
        let zeroLocation = CLLocation(latitude: 0.0, longitude: 0.0)

        service.setLastKnownLocation(zeroLocation)
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 1)
    }

    @Test
    func setLastKnownLocation_givenNegativeCoordinates_expectTrackCalled() async {
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(dataPipeline: pipelineMock)
        let negativeLocation = CLLocation(latitude: -33.8688, longitude: 151.2093)

        service.setLastKnownLocation(negativeLocation)
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 1)
        #expect(pipelineMock.trackInvocations.first?.properties["latitude"] as? Double == -33.8688)
        #expect(pipelineMock.trackInvocations.first?.properties["longitude"] as? Double == 151.2093)
    }

    // MARK: - requestLocationUpdate / stopLocationUpdates (use mock provider only)

    @Test
    func requestLocationUpdate_givenAuthorizedAndSuccess_expectTrackCalled() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setResult(.success(LocationSnapshot(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: Date(),
            horizontalAccuracy: 100,
            altitude: nil
        )))
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(
            mode: .manual,
            dataPipeline: pipelineMock,
            logger: LoggerMock(),
            locationProvider: mockProvider
        )

        service.requestLocationUpdate()
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 1)
        #expect(pipelineMock.trackInvocations.first?.properties["latitude"] as? Double == 37.7749)
        #expect(pipelineMock.trackInvocations.first?.properties["longitude"] as? Double == -122.4194)
    }

    @Test
    func requestLocationUpdate_givenTrackingDisabled_expectNoTrack() async {
        let mockProvider = MockLocationProvider()
        let pipelineMock = DataPipelineTrackingMock()
        let service = makeImplementation(
            mode: .off,
            dataPipeline: pipelineMock,
            logger: LoggerMock(),
            locationProvider: mockProvider
        )

        service.requestLocationUpdate()
        await yieldForLocationTask()

        #expect(pipelineMock.trackCallsCount == 0)
        let requestCount = await mockProvider.requestLocationCallCount
        #expect(requestCount == 0)
    }

    @Test
    func stopLocationUpdates_expectCancelCalledOnProvider() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setResult(.success(LocationSnapshot(
            latitude: 0, longitude: 0, timestamp: Date(), horizontalAccuracy: 0, altitude: nil
        )))
        let service = makeImplementation(
            mode: .manual,
            dataPipeline: DataPipelineTrackingMock(),
            logger: LoggerMock(),
            locationProvider: mockProvider
        )

        service.requestLocationUpdate()
        await yieldForLocationTask()
        service.stopLocationUpdates()
        await yieldForLocationTask()

        let cancelCount = await mockProvider.cancelCallCount
        #expect(cancelCount >= 1)
    }

    // MARK: - Lifecycle observer integration (setUpLifecycleObserver + StubAppLifecycleNotifying)

    @Test
    func setUpLifecycleObserver_givenOnAppStartAndStub_whenSimulateDidBecomeActive_expectRequestLocationUpdateTriggered() async {
        let stub = StubAppLifecycleNotifying()
        let mockProvider = MockLocationProvider()
        await mockProvider.setResult(.success(LocationSnapshot(
            latitude: 0, longitude: 0, timestamp: Date(), horizontalAccuracy: 0, altitude: nil
        )))
        let service = makeImplementation(
            mode: .onAppStart,
            locationProvider: mockProvider,
            lifecycleNotifying: stub
        )
        await service.setUpLifecycleObserver()

        stub.simulateDidBecomeActive()
        await yieldForLocationTask()

        let requestCount = await mockProvider.requestLocationCallCount
        #expect(requestCount >= 1)
    }

    @Test
    func setUpLifecycleObserver_givenStub_whenSimulateDidEnterBackground_expectStopLocationUpdatesTriggered() async {
        let stub = StubAppLifecycleNotifying()
        let mockProvider = MockLocationProvider()
        let service = makeImplementation(
            locationProvider: mockProvider,
            lifecycleNotifying: stub
        )
        await service.setUpLifecycleObserver()

        stub.simulateDidEnterBackground()
        await yieldForLocationTask()

        let cancelCount = await mockProvider.cancelCallCount
        #expect(cancelCount >= 1)
    }

    @Test
    func setUpLifecycleObserver_givenOnAppStartAndStateProviderSaysActive_expectRequestLocationUpdateTriggeredImmediately() async {
        let stubLifecycle = StubAppLifecycleNotifying()
        let stubState = StubApplicationStateProvider()
        stubState.setApplicationState(.active)
        let mockProvider = MockLocationProvider()
        await mockProvider.setResult(.success(LocationSnapshot(
            latitude: 0, longitude: 0, timestamp: Date(), horizontalAccuracy: 0, altitude: nil
        )))
        let service = makeImplementation(
            mode: .onAppStart,
            locationProvider: mockProvider,
            lifecycleNotifying: stubLifecycle,
            applicationStateProvider: stubState
        )
        await service.setUpLifecycleObserver()
        await yieldForLocationTask()

        let requestCount = await mockProvider.requestLocationCallCount
        #expect(requestCount >= 1)
    }
}
