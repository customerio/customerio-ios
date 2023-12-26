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
    }

    private func initializeEventBusHandler() -> EventBusHandler {
        EventBusHandler(
            eventBus: mockEventBus,
            eventCache: mockEventCache,
            eventStorage: mockEventStorage,
            logger: log
        )
    }

    func testLoadEventsFromStorageLoadsEventsCorrectly() async throws {
        _ = initializeEventBusHandler()

        // Expectation to wait for loadEvents to complete
        let loadEventsExpectation = XCTestExpectation(description: "Waiting for loadEvents to complete")

        // Mock action to fulfill the expectation
        mockEventStorage.loadEventsClosure = { _ in
            loadEventsExpectation.fulfill()
            return [] // Return an empty array or mock data as needed
        }

        // Wait for the loadEvents operation to complete
        await fulfillment(of: [loadEventsExpectation], timeout: 2)

        // Then (Actual): Verify that loadEvents was called for all event types
        XCTAssertEqual(mockEventStorage.loadEventsCallsCount, EventTypesRegistry.allEventTypes().count, "loadEvents should be called once during initialization")
    }

    // MARK: - Event Posting Tests

    func testEventPosting() async throws {
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
        await fulfillment(of: [postEventExpectation], timeout: 2)
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
        XCTAssertEqual((mockEventBus.postReceivedArguments as? ProfileIdentifiedEvent)?.identifier, event.identifier, "The correct event should be posted")
        XCTAssertTrue(mockEventCache.addEventCalled, "post should be called on EventBus")
    }

    func testPostEventWithObserversDoesNotStoreEvent() async throws {
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
        await fulfillment(of: [postEventExpectation], timeout: 2)

        // Then (Actual): Verify that post was called on EventBus and not stored in EventStorage
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 0, "Event should not be stored if there are observers")
    }

    func testPostEventWithoutObserversStoresEvent() async throws {
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
        await fulfillment(of: [postEventExpectation], timeout: 2)

        // Then: Verify that post was called on EventBus and event was stored
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 1, "Event should be stored if there are no observers")
    }

    // MARK: - Event Removal Tests

    func testEventRemovalFromStorageAfterBeingSent() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: An event that is posted to EventBusHandler and stored because there are no observers initially
        let event = ScreenViewedEvent(name: String.random)
        // Simulate no observers at the time of posting
        mockEventBus.postReturnValue = false
        mockEventCache.getEventReturnValue = [event]
        eventBusHandler.postEvent(event)

        // Expectation for the observer registration and event replay
        let observerAddedAndEventReplayedExpectation = XCTestExpectation(description: "Observer added and event replayed")

        // Mock the actions for adding an observer and replaying events
        mockEventBus.postClosure = { _ in
            // Simulate event replay and successful posting to observer
            observerAddedAndEventReplayedExpectation.fulfill()
            return true
        }

        // When: An observer is added after the event is stored
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in /* No action needed here */ }

        // Wait for the observer registration and event replay to complete
        await fulfillment(of: [observerAddedAndEventReplayedExpectation], timeout: 2)

        // Then: Verify that the event is removed from storage after being sent
        XCTAssertEqual(mockEventStorage.removeCallsCount, 1, "Event should be removed from storage after being successfully replayed to an observer")
    }

    // MARK: - Observer Replay Tests

    func testObserverIsReplayedEventsFromMemory() async throws {
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
        await fulfillment(of: [initialPostExpectation], timeout: 2)

        // Expectation for the observer registration
        let addObserverExpectation = XCTestExpectation(description: "Observer registration completed")
        mockEventBus.addObserverClosure = { _, _ in
            addObserverExpectation.fulfill()
        }

        // Expectation for the event replay
        let eventReplayExpectation = XCTestExpectation(description: "Event replay completed")
        mockEventBus.postClosure = { _ in
            eventReplayExpectation.fulfill()
            return true
        }

        // Add observer and trigger replay
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in /* No action needed here */ }

        // Wait for both the observer registration and event replay to complete
        await fulfillment(of: [addObserverExpectation, eventReplayExpectation], timeout: 4)

        // Assert that post was called twice (initial post + replay)
        XCTAssertEqual(mockEventBus.postCallsCount, 2, "post should be called twice, once for initial post and once for replay")
    }

    func testEventNotStoredInPersistentStorageIfObserversPresent() async throws {
        let eventBusHandler = initializeEventBusHandler()

        // Given: A mock event and EventBus with observers
        let event = RegisterDeviceTokenEvent(token: String.random)

        let postEventExpectation = XCTestExpectation(description: "Waiting for postEvent to complete")
        mockEventBus.postClosure = { _ in
            // Simulate observers present
            postEventExpectation.fulfill()
            return true
        }
        mockEventCache.getEventReturnValue = [event]

        // When: The event is posted
        eventBusHandler.postEvent(event)

        // Wait for the post operation to complete
        await fulfillment(of: [postEventExpectation], timeout: 2)

        // Then: Verify that post was called on EventBus and store was not called on EventStorage
        XCTAssertEqual(mockEventBus.postCallsCount, 1, "post should be called once on EventBus")
        XCTAssertEqual(mockEventStorage.storeCallsCount, 0, "store should not be called on EventStorage if observers are present")
    }

    func testObserverRegistrationAndEventPosting() async throws {
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
        await fulfillment(of: [observerRegistrationExpectation], timeout: 2)

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
        await fulfillment(of: [eventPostingExpectation], timeout: 2)

        // Then: Verify that post was called on EventBus
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
    }

    // MARK: - Observer Registration and Removal Tests

    func testObserverRegistrationAndRemoval() async throws {
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

        await fulfillment(of: [addObserverExpectation], timeout: 2)

        let removeObserverExpectation = XCTestExpectation(description: "Waiting for removeObserver to complete")
        mockEventBus.removeObserverClosure = { _ in
            removeObserverExpectation.fulfill()
        }
        // When: The observer is removed
        eventBusHandler.removeObserver(for: ScreenViewedEvent.self)

        // Then: Verify removeObserver was called on the EventBus mock
        await fulfillment(of: [removeObserverExpectation], timeout: 2)
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
    }

    // MARK: - Observer Registration for Multiple Event Types Tests

    func testObserverRegistrationForMultipleEventTypes() async throws {
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

        await fulfillment(of: [addObserverExpectation1, addObserverExpectation2], timeout: 2)
        XCTAssertTrue(mockEventBus.addObserverCalled, "addObserver should be called on EventBus")
    }

    // MARK: - Removing All Observers for Specific Event Type Tests

    func testRemovingAllObserversForSpecificEventType() async throws {
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
        await fulfillment(of: [removeObserverExpectation], timeout: 2)
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
    }

    func testEventOrdering() async throws {
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
        eventBusHandler.addObserver(TrackMetricEvent.self) { _ in /* No action needed here */ }

        // Wait for all events to be replayed
        let replayExpectation = XCTestExpectation(description: "Waiting for replayEvents to complete")
        var replayedEventsCount = 0
        mockEventBus.postClosure = { event in
            if event is TrackMetricEvent {
                replayedEventsCount += 1
                if replayedEventsCount == events.count {
                    replayExpectation.fulfill()
                }
            }
            return true
        }

        await fulfillment(of: [replayExpectation], timeout: 4)

        // Retrieve the events from the mock memory storage
        let storedEvents = mockEventCache.getEvent(TrackMetricEvent.key) as? [TrackMetricEvent]

        // Assert that the events were replayed in the order they were posted
        XCTAssertEqual(storedEvents?.map(\.deliveryID), events.map(\.deliveryID), "Events should be replayed in the order they were posted")
    }

    // MARK: - Event Memory Cachce Tests

    func testEventStorageInMemoryWhenNoObserversPresent() async throws {
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
        await fulfillment(of: [postEventExpectation], timeout: 2)

        // Then: Verify the event is stored in memory
        XCTAssertEqual(mockEventCache.addEventCallsCount, 1, "Event should be stored in memory")
        XCTAssertEqual((mockEventCache.addEventReceivedArguments as? ProfileIdentifiedEvent)?.identifier, event.identifier, "Stored event should match the posted event")
    }

    func testSuccessfulEventPostWithLaterObserverRegistration() async throws {
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

        // Mock the action for event replay
        mockEventBus.postClosure = { receivedEvent in
            if let replayedEvent = receivedEvent as? ProfileIdentifiedEvent,
               replayedEvent.identifier == event.identifier { // Compare with the identifier of the original event
                eventReplayExpectation.fulfill()
            }
            return true
        }

        // Add observer to trigger replay
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in /* No action needed here */ }

        // Wait for both observer registration and event replay to complete
        await fulfillment(of: [observerAddedExpectation, eventReplayExpectation], timeout: 2)
    }

    func testUnsuccessfulEventPostWithLaterObserverRegistration() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let event = ProfileIdentifiedEvent(identifier: "TestID")
        mockEventBus.postReturnValue = false // Simulate unsuccessful event post (no observers)
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

        // Mock the action for event replay
        mockEventBus.postClosure = { receivedEvent in
            if let replayedEvent = receivedEvent as? ProfileIdentifiedEvent,
               replayedEvent.identifier == event.identifier {
                eventReplayExpectation.fulfill()
            }
            return true
        }

        // Add observer to trigger replay
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in /* No action needed here */ }

        // Wait for both observer registration and event replay to complete
        await fulfillment(of: [observerAddedExpectation, eventReplayExpectation], timeout: 2)
    }

    func testReplayEventsAfterSessionRestart() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let event = ProfileIdentifiedEvent(identifier: "TestID")
        // Simulate event stored in persistent storage and loaded after session restart
        mockEventStorage.loadEventsReturnValue = [event]
        mockEventCache.getEventReturnValue = [event]

        // Trigger loading events from storage (simulating a session restart)
        await eventBusHandler.loadEventsFromStorage()

        // Expectation for event replay
        let eventReplayExpectation = XCTestExpectation(description: "Event replayed")

        // Mock the action for event replay
        mockEventBus.postClosure = { receivedEvent in
            if let replayedEvent = receivedEvent as? ProfileIdentifiedEvent,
               replayedEvent.identifier == event.identifier {
                eventReplayExpectation.fulfill()
            }
            return true
        }

        // Add observer to trigger replay
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in /* No action needed here */ }

        // Wait for the event replay to complete
        await fulfillment(of: [eventReplayExpectation], timeout: 2)
    }

    func testMultipleEventsHandling() async throws {
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
