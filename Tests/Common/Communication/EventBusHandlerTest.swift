@testable import CioInternalCommon
import Combine
import SharedTests
import XCTest

class EventBusHandlerTest: UnitTest {
    var eventBusHandler: EventBusHandler!
    var mockEventBus = EventBusMock()
    var mockEventStorage = EventStorageMock()

    override func setUp() {
        super.setUp()
        mockEventStorage.loadEventsReturnValue = []
        eventBusHandler = EventBusHandler(eventBus: mockEventBus, eventStorage: mockEventStorage)
    }

    func testLoadEventsFromStorageLoadsEventsCorrectly() {
        // Then (Actual): Verify that loadEvents was called for all event types and check how EventBusHandler handles the loaded events
        XCTAssertEqual(mockEventStorage.loadEventsCallsCount, EventTypesRegistry.allEventTypes().count, "loadEvents should be called once during initialization")
        // Additional assertions based on EventBusHandler's behavior with the loaded events
    }

    func testEventPosting() {
        // Given: A mock event
        let event = ProfileIdentifiedEvent(identifier: String.random)
        mockEventBus.postReturnValue = true

        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Then: Verify post was called on EventBus with the correct event
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
        XCTAssertEqual((mockEventBus.postReceivedArguments?.event as? ProfileIdentifiedEvent)?.identifier, event.identifier, "The correct event should be posted")
    }

    func testPostEventWithObserversDoesNotStoreEvent() {
        // Given: A mock event and EventBus with observers
        let event = ResetEvent()
        mockEventBus.postReturnValue = true // Assume there are observers

        // When (Expected): Post an event
        eventBusHandler.postEvent(event)

        // Then (Actual): Verify that post was called on EventBus and not stored in EventStorage
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 0, "Event should not be stored if there are observers")
    }

    func testPostEventWithoutObserversStoresEvent() {
        // Given: A mock event and EventBus without observers
        let event = TrackMetricEvent(deliveryID: String.random, event: String.random, deviceToken: String.random)
        mockEventBus.postReturnValue = false // Assume there are no observers

        // When (Expected): Post an event
        eventBusHandler.postEvent(event)

        // Then (Actual): Verify that post was called on EventBus and event was stored
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 1, "Event should be stored if there are no observers")
    }

    func testEventRemovalFromStorageAfterBeingSent() {
        // Given: An event that is in storage and needs to be removed after being sent
        let event = ScreenViewedEvent(name: String.random)
        mockEventBus.postReturnValue = true
        eventBusHandler.postEvent(event)

        // When (Expected): Replay events to send them to observers
        mockEventBus.postReturnValue = true
        eventBusHandler.replayEvents(forType: ScreenViewedEvent.self)

        // Then (Actual): Verify that remove was called on EventStorage
        XCTAssertEqual(mockEventStorage.removeCallsCount, 1, "Event should be removed from storage after being sent")
    }

    func testObserverIsReplayedEventsFromMemory() {
        // Given: An event posted to EventBusHandler
        let event = ScreenViewedEvent(name: String.random)
        mockEventBus.postReturnValue = false // Simulate no observers at the time of posting
        eventBusHandler.postEvent(event)

        // When: An observer is added
        eventBusHandler.addObserver(ScreenViewedEvent.self) { receivedEvent in
            // Then: The observer's action should be called with the replayed event
            XCTAssertEqual(event.name, receivedEvent.name, "The replayed event should match the posted event")
        }

        XCTAssertEqual(mockEventBus.postCallsCount, 2, "post should be called twice, second time for replay")

        // Then: Verify that the post method was called with the ScreenViewedEvent during replay
        let didReplayEvent = mockEventBus.postReceivedInvocations.contains { invocation in
            guard let replayedEvent = invocation.event as? ScreenViewedEvent else { return false }
            return replayedEvent.name == event.name
        }
        XCTAssertTrue(didReplayEvent, "The ScreenViewedEvent should have been replayed to the observer")
    }

    func testEventNotStoredInPersistentStorageIfObserversPresent() {
        // Given: A mock event and EventBus with observers
        let event = RegisterDeviceTokenEvent(token: String.random)
        mockEventBus.postReturnValue = true // Simulate observers present

        // When (Expected): Post an event
        eventBusHandler.postEvent(event)

        // Then (Actual): Verify post was called on EventBus and store was not called on EventStorage
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 0, "store should not be called on EventStorage if observers are present")
    }

    func testObserverRegistrationAndEventPosting() {
        // Given: An observer action for a specific event type
        let observerAction: (ScreenViewedEvent) -> Void = { _ in }

        // When: The observer is added
        eventBusHandler.addObserver(ScreenViewedEvent.self, action: observerAction)

        // Then: Verify addObserver was called on the EventBus mock
        XCTAssertTrue(mockEventBus.addObserverCalled, "addObserver should be called on EventBus")
        XCTAssertEqual(mockEventBus.addObserverReceivedArguments?.eventType, ScreenViewedEvent.key, "Observer should be registered for the correct event type")

        let event = ScreenViewedEvent(name: String.random)
        mockEventBus.postReturnValue = true // Simulate observers present
        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Then: Verify that post was called on EventBus and observer was notified
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
    }

    func testObserverRegistrationAndRemoval() {
        // Given: An observer action for a specific event type
        let observerAction: (ScreenViewedEvent) -> Void = { _ in }
        eventBusHandler.addObserver(ScreenViewedEvent.self, action: observerAction)

        // Then: Verify addObserver was called on the EventBus mock
        XCTAssertTrue(mockEventBus.addObserverCalled, "addObserver should be called on EventBus")
        XCTAssertEqual(mockEventBus.addObserverReceivedArguments?.eventType, ScreenViewedEvent.key, "Observer should be registered for ScreenViewedEvent")

        // When: The observer is removed
        eventBusHandler.removeObserver(for: ScreenViewedEvent.self)

        // Then: Verify removeObserver was called on the EventBus mock
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
        XCTAssertEqual(mockEventBus.removeObserverReceivedArguments, ScreenViewedEvent.key, "Observer for ScreenViewedEvent should be removed")
    }

    func testObserverRegistrationForMultipleEventTypes() {
        // Given: Observers for different event types are registered
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in }

        // Then: Verify addObserver was called on the EventBus mock for both event types
        let profileObserverAdded = mockEventBus.addObserverReceivedInvocations.contains { $0.eventType == ProfileIdentifiedEvent.key }
        let screenViewObserverAdded = mockEventBus.addObserverReceivedInvocations.contains { $0.eventType == ScreenViewedEvent.key }
        XCTAssertTrue(profileObserverAdded, "Observer for ProfileIdentifiedEvent should be registered")
        XCTAssertTrue(screenViewObserverAdded, "Observer for ScreenViewedEvent should be registered")
    }

    func testRemovingAllObserversForSpecificEventType() {
        // Given: Observers for a specific event type are added
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }

        // When: All observers for that event type are removed
        eventBusHandler.removeObserver(for: ProfileIdentifiedEvent.self)

        // Then: Verify removeObserver was called on the EventBus mock for the specific event type
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
        XCTAssertEqual(mockEventBus.removeObserverReceivedArguments, ProfileIdentifiedEvent.key, "All observers for ProfileIdentifiedEvent should be removed")
    }
}
