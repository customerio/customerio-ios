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
        logger: LoggerMock = LoggerMock()
    ) -> LocationServicesImplementation {
        let config = LocationConfig(enableLocationTracking: enableTracking)
        return LocationServicesImplementation(
            config: config,
            logger: logger,
            eventBusHandler: eventBusHandler
        )
    }

    @Test
    func setLastKnownLocation_givenTrackingDisabled_expectNoEventPosted() {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(enableTracking: false, eventBusHandler: eventBusHandlerMock)
        let validLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        service.setLastKnownLocation(validLocation)

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func setLastKnownLocation_givenInvalidCoordinates_expectNoEventPosted() {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let invalidLocation = CLLocation(latitude: 91.0, longitude: 181.0)

        service.setLastKnownLocation(invalidLocation)

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func setLastKnownLocation_givenValidLocation_expectEventPostedWithCorrectData() {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let expectedLatitude = 37.7749
        let expectedLongitude = -122.4194
        let validLocation = CLLocation(latitude: expectedLatitude, longitude: expectedLongitude)

        service.setLastKnownLocation(validLocation)

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event != nil)
        if let event {
            #expect(event.location.latitude == expectedLatitude)
            #expect(event.location.longitude == expectedLongitude)
        }
    }

    @Test
    func setLastKnownLocation_givenMultipleCalls_expectMultipleEventsPosted() {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let location2 = CLLocation(latitude: 40.7128, longitude: -74.0060)

        service.setLastKnownLocation(location1)
        service.setLastKnownLocation(location2)

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
    func setLastKnownLocation_givenZeroCoordinates_expectEventPosted() {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let zeroLocation = CLLocation(latitude: 0.0, longitude: 0.0)

        service.setLastKnownLocation(zeroLocation)

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
    }

    @Test
    func setLastKnownLocation_givenNegativeCoordinates_expectEventPosted() {
        let eventBusHandlerMock = EventBusHandlerMock()
        let service = makeImplementation(eventBusHandler: eventBusHandlerMock)
        let negativeLocation = CLLocation(latitude: -33.8688, longitude: 151.2093)

        service.setLastKnownLocation(negativeLocation)

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event != nil)
        if let event {
            #expect(event.location.latitude == -33.8688)
            #expect(event.location.longitude == 151.2093)
        }
    }
}
