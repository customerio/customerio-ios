@testable import CioInternalCommon
@testable import CioLocation
import CoreLocation
import SharedTests
import Testing

@Suite("Location")
struct LocationServicesImplementationTests {
    private func makeImplementation(
        enableTracking: Bool = true,
        eventBusHandler: EventBusHandlerMock = EventBusHandlerMock(),
        logger: LoggerMock = LoggerMock(),
        locationProvider: MockLocationProvider = MockLocationProvider()
    ) -> LocationServicesImplementation {
        let config = LocationConfig(enableLocationTracking: enableTracking)
        return LocationServicesImplementation(
            config: config,
            logger: logger,
            eventBusHandler: eventBusHandler,
            locationProvider: locationProvider
        )
    }

    /// Yields so the fire-and-forget task from requestLocationUpdateOnce() can run (no sleep).
    private func yieldForLocationTask() async {
        for _ in 0 ..< 40 {
            await Task.yield()
        }
    }

    @Test
    func setLastKnownLocation_givenTrackingDisabled_expectNoEventPosted() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(enableTracking: false, eventBusHandler: eventBusHandlerMock)
        let validLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        service.setLastKnownLocation(validLocation)
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func setLastKnownLocation_givenInvalidCoordinates_expectNoEventPosted() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let invalidLocation = CLLocation(latitude: 91.0, longitude: 181.0)

        service.setLastKnownLocation(invalidLocation)
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func setLastKnownLocation_givenValidLocation_expectEventPostedWithCorrectData() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let expectedLatitude = 37.7749
        let expectedLongitude = -122.4194
        let validLocation = CLLocation(latitude: expectedLatitude, longitude: expectedLongitude)

        service.setLastKnownLocation(validLocation)
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event != nil)
        if let event {
            #expect(event.location.latitude == expectedLatitude)
            #expect(event.location.longitude == expectedLongitude)
        }
    }

    @Test
    func setLastKnownLocation_givenMultipleCalls_expectMultipleEventsPosted() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let location2 = CLLocation(latitude: 40.7128, longitude: -74.0060)

        service.setLastKnownLocation(location1)
        service.setLastKnownLocation(location2)
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 2)
        let firstEvent = eventBusHandlerMock.postEventReceivedInvocations[0] as? TrackLocationEvent
        let secondEvent = eventBusHandlerMock.postEventReceivedInvocations[1] as? TrackLocationEvent
        #expect(firstEvent != nil)
        #expect(secondEvent != nil)
        if let firstEvent, let secondEvent {
            #expect(firstEvent.location.latitude == 37.7749)
            #expect(secondEvent.location.latitude == 40.7128)
        }
    }

    @Test
    func setLastKnownLocation_givenZeroCoordinates_expectEventPosted() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let zeroLocation = CLLocation(latitude: 0.0, longitude: 0.0)

        service.setLastKnownLocation(zeroLocation)
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
    }

    @Test
    func setLastKnownLocation_givenNegativeCoordinates_expectEventPosted() async {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let negativeLocation = CLLocation(latitude: -33.8688, longitude: 151.2093)

        service.setLastKnownLocation(negativeLocation)
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event != nil)
        if let event {
            #expect(event.location.latitude == -33.8688)
            #expect(event.location.longitude == 151.2093)
        }
    }

    // MARK: - requestLocationUpdateOnce / stopLocationUpdates (use mock provider only)

    @Test
    func requestLocationUpdateOnce_givenAuthorizedAndSuccess_expectEventPosted() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setResult(.success(LocationSnapshot(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: Date(),
            horizontalAccuracy: 100,
            altitude: nil
        )))
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(
            enableTracking: true,
            eventBusHandler: eventBusHandlerMock,
            logger: LoggerMock(),
            locationProvider: mockProvider
        )

        service.requestLocationUpdateOnce()
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event != nil)
        #expect(event?.location.latitude == 37.7749)
        #expect(event?.location.longitude == -122.4194)
    }

    @Test
    func requestLocationUpdateOnce_givenTrackingDisabled_expectNoEvent() async {
        let mockProvider = MockLocationProvider()
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(
            enableTracking: false,
            eventBusHandler: eventBusHandlerMock,
            logger: LoggerMock(),
            locationProvider: mockProvider
        )

        service.requestLocationUpdateOnce()
        await yieldForLocationTask()

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
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
            enableTracking: true,
            eventBusHandler: EventBusHandlerMock(),
            logger: LoggerMock(),
            locationProvider: mockProvider
        )

        service.requestLocationUpdateOnce()
        await yieldForLocationTask()
        await service.stopLocationUpdates()

        let cancelCount = await mockProvider.cancelCallCount
        #expect(cancelCount >= 1)
    }
}
