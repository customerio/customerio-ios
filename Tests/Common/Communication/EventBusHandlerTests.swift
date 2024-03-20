@testable import CioInternalCommon
import Combine
import SharedTests
import XCTest

class EventBusHandlerTest: UnitTest {
    var mockEventBus = EventBusMock()
    var mockEventStorage = EventStorageMock()
    var mockEventCache = EventCacheMock()

    override func setUp() {
        super.setUp()
        mockEventStorage.loadEventsReturnValue = []
        mockEventCache.getEventReturnValue = []
    }

    private func initializeEventBusHandler() -> EventBusHandler {
        CioEventBusHandler(
            eventBus: mockEventBus,
            eventCache: mockEventCache,
            eventStorage: mockEventStorage,
            logger: log
        )
    }

    func test_initialization_givenEventBusHandler_expectEventsLoadedFromStorage() async throws {
        _ = initializeEventBusHandler()

        // Expectation to wait for loadEvents to complete
        let loadEventsExpectation = XCTestExpectation(description: "Waiting for loadEvents to complete")

        // Mock action to fulfill the expectation
        mockEventStorage.loadEventsClosure = { _ in
            loadEventsExpectation.fulfill()
            return [] // Return an empty array or mock data as needed
        }

        // Wait for the loadEvents operation to complete
        await fulfillment(of: [loadEventsExpectation], timeout: 5.0)

        // Then (Actual): Verify that loadEvents was called for all event types
        XCTAssertEqual(mockEventStorage.loadEventsCallsCount, EventTypesRegistry.allEventTypes().count, "loadEvents should be called once during initialization")
    }

    // MARK: - Event Posting Tests

    func test_postEvent_givenEventPosted_expectEventBusPostCalled() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: A mock event
        let event = ProfileIdentifiedEvent(identifier: String.random)
        mockEventBus.postReturnValue = true

        let postEventExpectation = XCTestExpectation(description: "Waiting for postEvent to complete")
        mockEventBus.postClosure = { _ in
            postEventExpectation.fulfill()
            return true
        }

        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Then: Verify post was called on EventBus with the correct event
        await fulfillment(of: [postEventExpectation], timeout: 5.0)
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
        XCTAssertEqual((mockEventBus.postReceivedArguments as? ProfileIdentifiedEvent)?.identifier, event.identifier, "The correct event should be posted")
        XCTAssertTrue(mockEventCache.addEventCalled, "cache should have stored the event")
    }

    func test_postEvent_givenObserversPresent_expectEventNotStoredInPersistentStorage() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: A mock event and EventBus with observers
        let event = ResetEvent()
        mockEventBus.postReturnValue = true // Assume there are observers

        // Expectation for the postEvent call
        let postEventExpectation = XCTestExpectation(description: "Waiting for postEvent to complete")
        mockEventBus.postClosure = { _ in
            postEventExpectation.fulfill()
            return true
        }

        // When (Expected): Post an event
        eventBusHandler.postEvent(event)

        // Wait for the postEvent operation to complete
        await fulfillment(of: [postEventExpectation], timeout: 5.0)

        // Then (Actual): Verify that post was called on EventBus and not stored in EventStorage
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 0, "Event should not be stored if there are observers")
    }

    func test_postEvent_givenNoObservers_expectEventStoredInFile() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: A mock event and EventBus without observers
        let event = TrackMetricEvent(deliveryID: String.random, event: String.random, deviceToken: String.random)

        let postEventExpectation = XCTestExpectation(description: "Waiting for postEvent to complete")
        mockEventBus.postClosure = { _ in
            postEventExpectation.fulfill()
            // Assume there are no observers
            return false
        }

        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Wait for the post operation to complete
        await fulfillment(of: [postEventExpectation], timeout: 5.0)

        // Then: Verify that post was called on EventBus and event was stored
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 1, "Event should be stored if there are no observers")
    }

    func test_postEvent_givenTimestampedEvent_expectObserverReceivesCorrectTimestamp() async throws {
        let eventBusHandler = initializeEventBusHandler()
        let eventPostedTimestamp = Date()
        let event = ResetEvent(timestamp: eventPostedTimestamp)

        let eventReceivedExpectation = XCTestExpectation(description: "Event received by observer")
        var receivedEventTimestamp: Date?

        mockEventBus.postClosure = { event in
            receivedEventTimestamp = event.timestamp
            eventReceivedExpectation.fulfill()
            return true
        }

        eventBusHandler.postEvent(event)

        await XCTWaiter().fulfillment(of: [eventReceivedExpectation], timeout: 5.0)

        XCTAssertEqual(receivedEventTimestamp, eventPostedTimestamp, "The timestamp received by the observer does not match the event's posted timestamp.")
    }

    func test_postEvent_givenMultipleObservers_expectSingleNotificationPerObserver() async throws {
        let eventBusHandler = initializeEventBusHandler()
        let event = RegisterDeviceTokenEvent(token: String.random)

        // Simulate event caching for replay
        mockEventCache.getEventReturnValue = [event]

        // Expectations
        let firstObserverReceivedExpectation = XCTestExpectation(description: "First observer should receive event only once")
        firstObserverReceivedExpectation.expectedFulfillmentCount = 1
        let secondObserverReceivedExpectation = XCTestExpectation(description: "Second observer should receive event only once")
        secondObserverReceivedExpectation.expectedFulfillmentCount = 1

        mockEventBus.postClosure = { _ in
            firstObserverReceivedExpectation.fulfill()
            return true
        }

        // Register first observer
        eventBusHandler.addObserver(RegisterDeviceTokenEvent.self) { _ in
            // it will be recieved via notification center hence the mocks
        }

        // Post the event
        eventBusHandler.postEvent(event)

        // Register second observer
        eventBusHandler.addObserver(RegisterDeviceTokenEvent.self) { _ in
            // Second observer action, replay is supposed to happen
            secondObserverReceivedExpectation.fulfill()
        }

        // Wait for expectations
        await XCTWaiter().fulfillment(of: [firstObserverReceivedExpectation, secondObserverReceivedExpectation], timeout: 5.0)
    }

    // MARK: - Event Removal Tests

    func test_eventRemoval_givenEventSentToObserver_expectEventRemovedFromStorage() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: An event that is posted to EventBusHandler and stored because there are no observers initially
        let event = ScreenViewedEvent(name: String.random)
        // Simulate no observers at the time of posting
        mockEventBus.postReturnValue = false
        mockEventCache.getEventReturnValue = [event]
        eventBusHandler.postEvent(event)

        // Expectation for the observer registration and event replay
        let observerAddedAndEventReplayedExpectation = XCTestExpectation(description: "Observer added and event replayed")

        // When: An observer is added after the event is stored
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in
            // event should be replayed
            observerAddedAndEventReplayedExpectation.fulfill()
        }

        // Wait for the observer registration and event replay to complete
        await fulfillment(of: [observerAddedAndEventReplayedExpectation], timeout: 5.0)

        // Then: Verify that the event is removed from storage after being sent
        XCTAssertEqual(mockEventStorage.removeCallsCount, 1, "Event should be removed from storage after being successfully replayed to an observer")
    }

    // MARK: - Observer Replay Tests

    func test_observerReplay_givenEventsInMemory_expectEventsReplayedToObserver() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let event = ScreenViewedEvent(name: String.random)

        // Expectation for the initial post event
        let initialPostExpectation = XCTestExpectation(description: "Initial post event completed")
        mockEventBus.postClosure = { _ in
            initialPostExpectation.fulfill()
            return false
        }
        mockEventCache.getEventReturnValue = [event]

        // Post the event
        eventBusHandler.postEvent(event)

        // Wait for the initial post to complete
        await fulfillment(of: [initialPostExpectation], timeout: 5.0)

        // Expectation for the observer registration
        let addObserverExpectation = XCTestExpectation(description: "Observer registration completed")
        mockEventBus.addObserverClosure = { _, _ in
            addObserverExpectation.fulfill()
        }

        // Expectation for the event replay
        let eventReplayExpectation = XCTestExpectation(description: "Event replay completed")

        // Add observer and trigger replay
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in
            eventReplayExpectation.fulfill()
        }

        // Wait for both the observer registration and event replay to complete
        await fulfillment(of: [addObserverExpectation, eventReplayExpectation], timeout: 5.0)

        // Assert that post was called twice (initial post + replay)
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once, once for initial post and not for replay")
    }

    func test_observerRegistration_givenEventPosted_expectEventBusPostCalled() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Expectation for observer registration
        let observerRegistrationExpectation = XCTestExpectation(description: "Observer registration completed")

        // Mock action for observer registration
        mockEventBus.addObserverClosure = { _, _ in
            observerRegistrationExpectation.fulfill()
        }

        mockEventCache.getEventReturnValue = []

        // Given: An observer action for a specific event type
        let observerAction: (ScreenViewedEvent) -> Void = { _ in /* No action needed here */ }

        // When: The observer is added
        eventBusHandler.addObserver(ScreenViewedEvent.self, action: observerAction)

        // Wait for the observer registration to complete
        await fulfillment(of: [observerRegistrationExpectation], timeout: 5.0)

        // Verify addObserver was called on the EventBus mock
        XCTAssertTrue(mockEventBus.addObserverCalled, "addObserver should be called on EventBus")
        XCTAssertEqual(mockEventBus.addObserverReceivedArguments?.eventType, ScreenViewedEvent.key, "Observer should be registered for the correct event type")

        // Expectation for event posting
        let eventPostingExpectation = XCTestExpectation(description: "Event posted")

        // Mock action for event posting
        mockEventBus.postClosure = { _ in
            eventPostingExpectation.fulfill()
            return true // Simulate observers present
        }

        // Given: A mock event
        let event = ScreenViewedEvent(name: String.random)

        mockEventCache.getEventReturnValue = [event]

        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Wait for the event posting to complete
        await fulfillment(of: [eventPostingExpectation], timeout: 5.0)

        // Then: Verify that post was called on EventBus
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
    }

    // MARK: - Observer Registration and Removal Tests

    func test_observerRegistrationAndRemoval_givenObserverRegisteredAndRemoved_expectCorrectBehaviour() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: An observer action for a specific event type
        let observerAction: (ScreenViewedEvent) -> Void = { _ in }
        // Then: Verify addObserver was called on the EventBus mock
        let addObserverExpectation = XCTestExpectation(description: "Waiting for addObserver to complete")
        mockEventBus.addObserverClosure = { _, _ in
            addObserverExpectation.fulfill()
        }
        mockEventCache.getEventReturnValue = []

        eventBusHandler.addObserver(ScreenViewedEvent.self, action: observerAction)

        await fulfillment(of: [addObserverExpectation], timeout: 5.0)

        let removeObserverExpectation = XCTestExpectation(description: "Waiting for removeObserver to complete")
        mockEventBus.removeObserverClosure = { _ in
            removeObserverExpectation.fulfill()
        }
        // When: The observer is removed
        eventBusHandler.removeObserver(for: ScreenViewedEvent.self)

        // Then: Verify removeObserver was called on the EventBus mock
        await fulfillment(of: [removeObserverExpectation], timeout: 5.0)
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
    }

    // MARK: - Observer Registration for Multiple Event Types Tests

    func test_observerRegistration_givenMultipleEventTypes_expectObserversRegisteredForAll() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: Observers for different event types are registered
        let addObserverExpectation1 = XCTestExpectation(description: "Waiting for addObserver of type 1 to complete")
        let addObserverExpectation2 = XCTestExpectation(description: "Waiting for addObserver of type 2 to complete")

        // Then: Verify addObserver was called on the EventBus mock for both event types
        mockEventBus.addObserverClosure = { eventType, _ in
            if eventType == ProfileIdentifiedEvent.key {
                addObserverExpectation1.fulfill()
            } else if eventType == ScreenViewedEvent.key {
                addObserverExpectation2.fulfill()
            }
        }
        mockEventCache.getEventReturnValue = []

        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in }

        await fulfillment(of: [addObserverExpectation1, addObserverExpectation2], timeout: 5.0)
        XCTAssertTrue(mockEventBus.addObserverCalled, "addObserver should be called on EventBus")
    }

    // MARK: - Removing All Observers for Specific Event Type Tests

    func test_removingObservers_givenSpecificEventType_expectObserversRemovedForEventType() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: Observers for a specific event type are added
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }

        let removeObserverExpectation = XCTestExpectation(description: "Waiting for removeObserver to complete")
        mockEventBus.removeObserverClosure = { _ in
            removeObserverExpectation.fulfill()
        }
        mockEventCache.getEventReturnValue = []
        // When: All observers for that event type are removed
        eventBusHandler.removeObserver(for: ProfileIdentifiedEvent.self)

        // Then: Verify removeObserver was called on the EventBus mock for the specific event type
        await fulfillment(of: [removeObserverExpectation], timeout: 5.0)
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
    }

    func test_eventOrdering_givenMultipleEventsPosted_expectEventsReplayedInOrder() async throws {
        // Initialize EventBusHandler
        let eventBusHandler = initializeEventBusHandler()

        // Prepare a series of events
        let events = (1 ... 5).map { TrackMetricEvent(deliveryID: "Event\($0)", event: "Test", deviceToken: "Token\($0)") }

        // Post each event to the EventBusHandler
        events.forEach {
            mockEventBus.postReturnValue = true
            eventBusHandler.postEvent($0)
        }

        // Set the returnValue for eventsForKey in the mock
        mockEventCache.getEventReturnValue = events

        // Add an observer to trigger the replay of events
        // Wait for all events to be replayed
        let replayExpectation = XCTestExpectation(description: "Waiting for replayEvents to complete")
        var replayedEventsCount = 0
        eventBusHandler.addObserver(TrackMetricEvent.self) { _ in
            replayedEventsCount += 1
            if replayedEventsCount == events.count {
                replayExpectation.fulfill()
            }
        }

        await fulfillment(of: [replayExpectation], timeout: 5)

        // Retrieve the events from the mock memory storage
        let storedEvents = mockEventCache.getEvent(TrackMetricEvent.key) as? [TrackMetricEvent]

        // Assert that the events were replayed in the order they were posted
        XCTAssertEqual(storedEvents?.map(\.deliveryID), events.map(\.deliveryID), "Events should be replayed in the order they were posted")
    }

    // MARK: - Event Memory Cachce Tests

    func test_eventStorageInMemory_givenNoObserversPresent_expectEventStoredInMemory() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: A mock event with no observers
        let event = ProfileIdentifiedEvent(identifier: "TestID")
        mockEventBus.postReturnValue = false // Simulate no observers

        // Expectation for the postEvent completion
        let postEventExpectation = XCTestExpectation(description: "Waiting for postEvent to complete")
        mockEventBus.postClosure = { _ in
            // Fulfill the expectation when the event is attempted to be posted
            postEventExpectation.fulfill()
            return false
        }

        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Wait for the postEvent operation to complete
        await fulfillment(of: [postEventExpectation], timeout: 5.0)

        // Then: Verify the event is stored in memory
        XCTAssertEqual(mockEventCache.addEventCallsCount, 1, "Event should be stored in memory")
        XCTAssertEqual((mockEventCache.addEventReceivedArguments as? ProfileIdentifiedEvent)?.identifier, event.identifier, "Stored event should match the posted event")
    }

    func test_successfulEventPost_givenLaterObserverRegistration_expectEventReplayed() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let event = ProfileIdentifiedEvent(identifier: "TestID")
        mockEventBus.postReturnValue = true // Simulate successful event post with observers
        mockEventCache.getEventReturnValue = [event]

        // Post the event
        eventBusHandler.postEvent(event)

        // Add the event to memory cache manually for simulation
        mockEventCache.addEvent(event: event)

        // Expectation for observer registration and event replay
        let observerAddedExpectation = XCTestExpectation(description: "Observer registration completed")
        let eventReplayExpectation = XCTestExpectation(description: "Event replayed")

        // Mock the action for observer registration completion
        mockEventBus.addObserverClosure = { _, _ in
            observerAddedExpectation.fulfill()
        }

        // Add observer to trigger replay
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { receivedEvent in
            if receivedEvent.identifier == event.identifier { // Compare with the identifier of the original event
                eventReplayExpectation.fulfill()
            }
        }

        // Wait for both observer registration and event replay to complete
        await fulfillment(of: [observerAddedExpectation, eventReplayExpectation], timeout: 5.0)
    }

    func test_unsuccessfulEventPost_givenLaterObserverRegistration_expectEventReplayed() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let event = ProfileIdentifiedEvent(identifier: "TestID")
        // Simulate unsuccessful event post (no observers)
        mockEventBus.postReturnValue = false
        // Add the event to memory cache manually for simulation
        mockEventCache.getEventReturnValue = [event]

        // Post the event
        eventBusHandler.postEvent(event)

        // Add the event to memory cache manually for simulation
        mockEventCache.addEvent(event: event)

        // Expectation for observer registration and event replay
        let observerAddedExpectation = XCTestExpectation(description: "Observer registration completed")
        let eventReplayExpectation = XCTestExpectation(description: "Event replayed")

        // Mock the action for observer registration completion
        mockEventBus.addObserverClosure = { _, _ in
            observerAddedExpectation.fulfill()
        }

        // Add observer to trigger replay
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { replayedEvent in
            if replayedEvent.identifier == event.identifier {
                eventReplayExpectation.fulfill()
            }
        }

        // Wait for both observer registration and event replay to complete
        await fulfillment(of: [observerAddedExpectation, eventReplayExpectation], timeout: 5.0)
    }

    func test_replayEvents_givenSessionRestart_expectEventsReplayedFromStorage() async throws {
        // Configure mockEventStorage to return the event as if it was stored from a previous session
        let event = ProfileIdentifiedEvent(identifier: "TestID")
        mockEventStorage.loadEventsClosure = { receivedType in
            if receivedType == ProfileIdentifiedEvent.key {
                return [event]
            } else {
                return []
            }
        }
        mockEventCache.getEventReturnValue = [event]

        // Initialize EventBusHandler, which will load events from storage
        let eventBusHandler = initializeEventBusHandler()

        // Expectation for event replay
        let eventReplayExpectation = XCTestExpectation(description: "Event replayed")

        // Add observer to trigger replay
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { receivedEvent in
            if receivedEvent.identifier == event.identifier {
                eventReplayExpectation.fulfill()
            }
        }

        // Wait for the event replay to complete
        await fulfillment(of: [eventReplayExpectation], timeout: 5.0)
    }

    func test_multipleEventsHandling_givenEventsPosted_expectEventsHandledCorrectly() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let events = (1 ... 3).map { ProfileIdentifiedEvent(identifier: "Event\($0)") }
        mockEventBus.postReturnValue = false // Simulate no observers for all events
        mockEventCache.getEventReturnValue = events

        // Post each event
        events.forEach { eventBusHandler.postEvent($0) }

        // Add each event to memory cache manually for simulation
        events.forEach { mockEventCache.addEvent(event: $0) }

        // Expectation for observer registration and event replay
        let observerAddedExpectation = XCTestExpectation(description: "Observer registration completed")
        let eventReplayExpectation = XCTestExpectation(description: "All events replayed")
        var replayedEventsCount = 0

        // Mock the action for observer registration completion and event replay
        mockEventBus.addObserverClosure = { _, _ in observerAddedExpectation.fulfill() }
        mockEventBus.postClosure = { receivedEvent in
            if receivedEvent is ProfileIdentifiedEvent {
                replayedEventsCount += 1
                if replayedEventsCount == events.count {
                    eventReplayExpectation.fulfill()
                }
            }
            return true
        }
    }
}
