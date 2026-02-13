@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("LocationOrchestrator")
struct LocationOrchestratorTests {
    private func makeOrchestrator(
        enableTracking: Bool = true,
        eventBusHandler: EventBusHandlerMock = EventBusHandlerMock(),
        logger: LoggerMock = LoggerMock(),
        locationProvider: MockLocationProvider
    ) -> LocationOrchestrator {
        let config = LocationConfig(enableLocationTracking: enableTracking)
        return LocationOrchestrator(
            config: config,
            logger: logger,
            eventBusHandler: eventBusHandler,
            locationProvider: locationProvider
        )
    }

    @Test
    func requestLocationUpdateOnce_givenTrackingDisabled_expectNoProviderCall() async {
        let mockProvider = MockLocationProvider()
        let orchestrator = makeOrchestrator(enableTracking: false, locationProvider: mockProvider)

        await orchestrator.requestLocationUpdateOnce()

        let requestCount = await mockProvider.requestLocationCallCount
        #expect(requestCount == 0)
    }

    @Test
    func requestLocationUpdateOnce_givenNotAuthorized_expectNoRequestLocation() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setAuthStatus(.denied)
        let eventBusHandlerMock = EventBusHandlerMock()
        let orchestrator = makeOrchestrator(eventBusHandler: eventBusHandlerMock, locationProvider: mockProvider)

        await orchestrator.requestLocationUpdateOnce()

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
        let requestCount = await mockProvider.requestLocationCallCount
        #expect(requestCount == 0)
    }

    @Test
    func requestLocationUpdateOnce_givenAuthorizedAndSuccess_expectEventPosted() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setAuthStatus(.authorizedWhenInUse)
        let snapshot = LocationSnapshot(
            latitude: 37.7749,
            longitude: -122.4194,
            timestamp: Date(),
            horizontalAccuracy: 100,
            altitude: nil
        )
        await mockProvider.setRequestLocationResult(.success(snapshot))
        let eventBusHandlerMock = EventBusHandlerMock()
        let orchestrator = makeOrchestrator(eventBusHandler: eventBusHandlerMock, locationProvider: mockProvider)

        await orchestrator.requestLocationUpdateOnce()

        #expect(eventBusHandlerMock.postEventCallsCount == 1)
        let event = eventBusHandlerMock.postEventArguments as? TrackLocationEvent
        #expect(event != nil)
        #expect(event?.location.latitude == 37.7749)
        #expect(event?.location.longitude == -122.4194)
    }

    @Test
    func requestLocationUpdateOnce_givenAuthorizedAndProviderThrows_expectNoEvent() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setAuthStatus(.authorizedWhenInUse)
        await mockProvider.setRequestLocationResult(.failure(LocationProviderError.timeout))
        let eventBusHandlerMock = EventBusHandlerMock()
        let orchestrator = makeOrchestrator(eventBusHandler: eventBusHandlerMock, locationProvider: mockProvider)

        await orchestrator.requestLocationUpdateOnce()

        #expect(eventBusHandlerMock.postEventCallsCount == 0)
    }

    @Test
    func requestLocationUpdateOnce_givenAuthorized_expectRequestLocationCalled() async {
        let mockProvider = MockLocationProvider()
        await mockProvider.setAuthStatus(.authorizedWhenInUse)
        await mockProvider.setRequestLocationResult(.success(LocationSnapshot(
            latitude: 0, longitude: 0, timestamp: Date(), horizontalAccuracy: 0, altitude: nil
        )))
        let orchestrator = makeOrchestrator(locationProvider: mockProvider)

        await orchestrator.requestLocationUpdateOnce()

        let requestCount = await mockProvider.requestLocationCallCount
        #expect(requestCount == 1)
    }
}
