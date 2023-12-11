@testable import CioInternalCommon
import Combine
import SharedTests
import XCTest

final class EventBusTests: UnitTest {
    var eventBus: EventBus!
    var subscriptions: Set<AnyCancellable>!

    override func setUpWithError() throws {
        eventBus = SharedEventBus(
            listenersRegistry: EventListenersManager())
        subscriptions = []
    }

    override func tearDownWithError() throws {
        eventBus = nil
        subscriptions = nil
    }
}

// MARK: - Events test

extension EventBusTests {
    func test_send_givenProfileIdentifiedEvent_expectEventReceived() throws {
        // given
        let expectedEvent = ProfileIdentifiedEvent(identifier: String.random)

        // and
        let eventExpectation = expectation(description: "Should receive ProfileIdentifiedEvent event")
        eventBus.onReceive(ProfileIdentifiedEvent.self) { actualEvent in
            if actualEvent == expectedEvent {
                eventExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        eventBus.send(expectedEvent)

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenProfileIdentifiedEventWithAnotherEventListener_expectNoEventReceived() throws {
        // given
        let eventExpectation = expectation(description: "Should not receive an event")
        eventExpectation.isInverted = true

        eventBus.onReceive(AnotherEvent.self) { _ in
            eventExpectation.fulfill()
        }
        .store(in: &subscriptions)

        // when
        eventBus.send(ProfileIdentifiedEvent(identifier: String.random))

        // then
        waitForExpectations(timeout: 1)
    }
}

// MARK: - Events with Params

extension EventBusTests {
    func test_send_givenEventWithParams_expectEventWithParamsReceived() throws {
        // given
        let expectedParams: [String: String] = [
            "planet": "Hoth",
            "distanceInParsecs": "10"
        ]

        // end
        let eventExpectation = expectation(description: "Should receive Screen event with custom parameters")
        eventBus.onReceive(ScreenViewedEvent.self) { actualParams in
            if actualParams.params == expectedParams {
                eventExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        eventBus.send(ScreenViewedEvent(name: "Planets", params: expectedParams))

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenEventWithoutParams_expectEventWithoutParamsReceived() throws {
        // given
        let eventExpectation = expectation(description: "Should receive Reset event without parameters")
        eventBus.onReceive(ResetEvent.self) { event in
            if event.params.isEmpty {
                eventExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        eventBus.send(ResetEvent())

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenEvent_andListeningForAnotherEvent_expectNoEventReceived() throws {
        // given
        let threadExpectation = expectation(description: "Should not receive an event")
        threadExpectation.isInverted = true

        eventBus.onReceive(ResetEvent.self) { _ in
            threadExpectation.fulfill()
        }
        .store(in: &subscriptions)

        // when
        eventBus.send(ProfileIdentifiedEvent(identifier: String.random))

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenAnEvent_andListeningForAnotherOnDifferentThread_expectNoEventReceived() throws {
        // given
        let threadExpectation = expectation(description: "Should not receive an event on the main thread")
        threadExpectation.isInverted = true

        eventBus.onReceive(ProfileIdentifiedEvent.self, performOn: DispatchQueue.main) { _ in
            threadExpectation.fulfill()
        }
        .store(in: &subscriptions)

        // when
        DispatchQueue.global(qos: .background).async {
            self.eventBus.send(ResetEvent())
        }

        // then
        waitForExpectations(timeout: 10)
    }
}

// MARK: - Threading

extension EventBusTests {
    func test_send_givenEventOnBackgroundThread_expectEventReceivedOnSameThread() throws {
        // given
        var sendThread: Thread?

        // and
        let threadExpectation = expectation(description: "Should receive an event on the same thread that was used to send the event")
        eventBus.onReceive(TrackMetricEvent.self) { _ in
            if Thread.current == sendThread {
                threadExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        DispatchQueue.global(qos: .background).async {
            sendThread = Thread.current
            self.eventBus.send(TrackMetricEvent(deliveryID: String.random, event: String.random, deviceToken: String.random))
        }

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenResetEventOnBackgroundThread_expectEventReceivedOnMainThread() throws {
        // given
        let threadExpectation = expectation(description: "Should receive an event on the main thread")
        eventBus.onReceive(ResetEvent.self, performOn: DispatchQueue.main) { _ in
            if Thread.current.isMainThread {
                threadExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        DispatchQueue.global(qos: .background).async {
            self.eventBus.send(ResetEvent())
        }

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenEventOnMainThread_expectEventReceivedOnBackgroundThread() throws {
        // given
        let threadExpectation = expectation(description: "Should receive an event on the background thread")
        eventBus.onReceive(DeleteDeviceTokenEvent.self, performOn: DispatchQueue.global(qos: .background)) { _ in
            if !Thread.current.isMainThread {
                threadExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        DispatchQueue.main.async {
            self.eventBus.send(DeleteDeviceTokenEvent())
        }

        // then
        waitForExpectations(timeout: 10)
    }
}

// MARK: - Other

extension EventBusTests {
    func test_send_givenEventWithMultipleSubscribers_expectMultipleEventsReceived() throws {
        // given
        let eventExpectation = expectation(description: "Should receive events")
        eventExpectation.expectedFulfillmentCount = 2

        eventBus.onReceive(AnotherEvent.self) { _ in
            eventExpectation.fulfill()
        }
        .store(in: &subscriptions)

        eventBus.onReceive(AnotherEvent.self) { _ in
            eventExpectation.fulfill()
        }
        .store(in: &subscriptions)

        // when
        eventBus.send(AnotherEvent())

        // then
        waitForExpectations(timeout: 10)
    }

    func test_send_givenEventWithNoStoredSubscription_expectNoEventReceived() throws {
        // given
        let threadExpectation = expectation(description: "Should not receive an event")
        threadExpectation.isInverted = true

        eventBus.onReceive(ProfileIdentifiedEvent.self) { _ in
            threadExpectation.fulfill()
        }
        // .store(in: &subscriptions) -> don't store subscription, so it is deallocated immediately

        // when
        eventBus.send(ProfileIdentifiedEvent(identifier: String.random))

        // then
        waitForExpectations(timeout: 1)
    }
}

// MARK: - Send response

extension EventBusTests {
    func test_sendEvent_givenNoSubscribers_expectFalseReturned() throws {
        // given
        let event = ProfileIdentifiedEvent(identifier: String.random)

        // when
        let wasEventHandled = eventBus.send(event)

        // then
        XCTAssertFalse(wasEventHandled, "Expected send to return false as there are no subscribers for the event")
    }

    func test_sendEvent_givenSubscribers_expectTrueReturned() throws {
        // given
        let event = RegisterDeviceTokenEvent(token: String.random)
        let eventExpectation = expectation(description: "Expect RegisterDeviceTokenEvent to be received")
        eventBus.onReceive(RegisterDeviceTokenEvent.self) { _ in
            eventExpectation.fulfill()
        }.store(in: &subscriptions)

        // when
        let wasEventHandled = eventBus.send(event)

        // then
        XCTAssertTrue(wasEventHandled, "Expected send to return true as there are subscribers for the event")
        waitForExpectations(timeout: 10)
    }
}

// MARK: - NewSubscriptionEvent Logic

extension EventBusTests {
    func test_send_givenNewSubscription_expectNewSubscriptionEventEmitted() throws {
        // given
        let newSubEventExpectation = expectation(description: "Should receive NewSubscriptionEvent for ProfileIdentifiedEvent")
        var newSubscriptionEventType: String?

        eventBus.onReceive(NewSubscriptionEvent.self) { newSubEvent in
            newSubscriptionEventType = newSubEvent.subscribedEventType
            newSubEventExpectation.fulfill()
        }.store(in: &subscriptions)

        // when
        eventBus.onReceive(ProfileIdentifiedEvent.self) { _ in }
            .store(in: &subscriptions)

        // then
        waitForExpectations(timeout: 10)
        XCTAssertEqual(newSubscriptionEventType, String(describing: ProfileIdentifiedEvent.self))
    }

    func test_send_givenRepeatedSubscription_expectNoNewSubscriptionEventEmitted() throws {
        // given
        let newSubEventExpectation = expectation(description: "Should not receive additional NewSubscriptionEvent for ProfileIdentifiedEvent")
        newSubEventExpectation.isInverted = true

        eventBus.onReceive(ProfileIdentifiedEvent.self) { _ in }
            .store(in: &subscriptions)

        eventBus.onReceive(NewSubscriptionEvent.self) { _ in
            newSubEventExpectation.fulfill()
        }.store(in: &subscriptions)

        // when
        eventBus.onReceive(ProfileIdentifiedEvent.self) { _ in }
            .store(in: &subscriptions)

        // then
        waitForExpectations(timeout: 2)
    }

    func test_send_givenNewSubscriptionToNewSubscriptionEvent_expectNoNewSubscriptionEventEmitted() throws {
        // given
        let newSubEventExpectation = expectation(description: "Should not receive NewSubscriptionEvent for its own subscription")
        newSubEventExpectation.isInverted = true

        eventBus.onReceive(NewSubscriptionEvent.self) { _ in
            newSubEventExpectation.fulfill()
        }.store(in: &subscriptions)

        // when
        eventBus.onReceive(NewSubscriptionEvent.self) { _ in }
            .store(in: &subscriptions)

        // then
        waitForExpectations(timeout: 2)
    }
}

// MARK: - Mocked data

private extension EventBusTests {
    struct AnotherEvent: EventRepresentable {
        var params: [String: String] = [:]
    }
}
