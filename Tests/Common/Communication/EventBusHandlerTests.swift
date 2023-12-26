@testable import CioInternalCommon
import Combine
import SharedTests
import XCTest

class EventBusHandlerTest: UnitTest {
    var mockEventBus = EventBusMock()
    var mockEventStorage = EventStorageMock()

    override func setUp() {
        super.setUp()
        mockEventStorage.loadEventsReturnValue = []
    }

    private func initializeEventBusHandler() -> EventBusHandler {
        EventBusHandler(eventBus: mockEventBus, eventStorage: mockEventStorage, logger: log)
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

        let event = ProfileIdentifiedEvent(identifier: String.random)
        mockEventBus.postReturnValue = true

        let postEventExpectation = XCTestExpectation(description: "Waiting for postEvent to complete")
        mockEventBus.postClosure = { _ in
            postEventExpectation.fulfill()
            return true
        }

        eventBusHandler.postEvent(event)

        await fulfillment(of: [postEventExpectation], timeout: 2)
        XCTAssertTrue(mockEventBus.postCalled, "post should be called on EventBus")
        XCTAssertEqual((mockEventBus.postReceivedArguments as? ProfileIdentifiedEvent)?.identifier, event.identifier, "The correct event should be posted")
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

        let event = ScreenViewedEvent(name: String.random)
        mockEventBus.postClosure = { _ in false }

        eventBusHandler.postEvent(event)

        let replayEventsExpectation = XCTestExpectation(description: "Waiting for replayEvents to complete")
        mockEventBus.postClosure = { _ in
            replayEventsExpectation.fulfill()
            return true
        }
        await eventBusHandler.replayEvents(forType: ScreenViewedEvent.self)

        await fulfillment(of: [replayEventsExpectation], timeout: 2)
        XCTAssertEqual(mockEventStorage.removeCallsCount, 1, "Event should be removed from storage after being sent")
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

        let observerAction: (ScreenViewedEvent) -> Void = { _ in }
        let addObserverExpectation = XCTestExpectation(description: "Waiting for addObserver to complete")
        mockEventBus.addObserverClosure = { _, _ in
            addObserverExpectation.fulfill()
        }

        eventBusHandler.addObserver(ScreenViewedEvent.self, action: observerAction)

        await fulfillment(of: [addObserverExpectation], timeout: 2)

        let removeObserverExpectation = XCTestExpectation(description: "Waiting for removeObserver to complete")
        mockEventBus.removeObserverClosure = { _ in
            removeObserverExpectation.fulfill()
        }

        eventBusHandler.removeObserver(for: ScreenViewedEvent.self)

        await fulfillment(of: [removeObserverExpectation], timeout: 2)
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
    }

    // MARK: - Observer Registration for Multiple Event Types Tests

    func testObserverRegistrationForMultipleEventTypes() async throws {
        let eventBusHandler = initializeEventBusHandler()

        let addObserverExpectation1 = XCTestExpectation(description: "Waiting for addObserver of type 1 to complete")
        let addObserverExpectation2 = XCTestExpectation(description: "Waiting for addObserver of type 2 to complete")

        mockEventBus.addObserverClosure = { eventType, _ in
            if eventType == ProfileIdentifiedEvent.key {
                addObserverExpectation1.fulfill()
            } else if eventType == ScreenViewedEvent.key {
                addObserverExpectation2.fulfill()
            }
        }

        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        eventBusHandler.addObserver(ScreenViewedEvent.self) { _ in }

        await fulfillment(of: [addObserverExpectation1, addObserverExpectation2], timeout: 2)
        XCTAssertTrue(mockEventBus.addObserverCalled, "addObserver should be called on EventBus")
    }

    // MARK: - Removing All Observers for Specific Event Type Tests

    func testRemovingAllObserversForSpecificEventType() async throws {
        let eventBusHandler = initializeEventBusHandler()

        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in }

        let removeObserverExpectation = XCTestExpectation(description: "Waiting for removeObserver to complete")
        mockEventBus.removeObserverClosure = { _ in
            removeObserverExpectation.fulfill()
        }

        eventBusHandler.removeObserver(for: ProfileIdentifiedEvent.self)

        await fulfillment(of: [removeObserverExpectation], timeout: 2)
        XCTAssertTrue(mockEventBus.removeObserverCalled, "removeObserver should be called on EventBus")
    }
}
