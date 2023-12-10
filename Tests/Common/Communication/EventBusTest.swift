@testable import CioInternalCommon
import Combine
import SharedTests
import XCTest

final class EventBusTests: UnitTest {
    var eventBus: EventBus!
    var subscriptions: Set<AnyCancellable>!

    override func setUpWithError() throws {
        eventBus = SharedEventBus(
            listenersRegistry: EventListenersManager(eventStorage: EventStorageMock()))
        subscriptions = []
    }

    override func tearDownWithError() throws {
        eventBus = nil
        subscriptions = nil
    }
}

// MARK: - Custom event

extension EventBusTests {
    func testSendingAndReceivingCustomEvent() throws {
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

    func testSendingOneEventAndListeningForAnotherEvent() throws {
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

// MARK: - Named event

extension EventBusTests {
    func testSendingAndReceivingNamedEventWithCustomParams() throws {
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
        eventBus.send(ScreenViewedEvent(params: expectedParams, name: "Planets"))

        // then
        waitForExpectations(timeout: 10)
    }

    func testSendingAndReceivingNamedEventWithoutParams() throws {
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

    func testSendingAnEventAndListeningForAnotherEvent() throws {
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

    func testSendAnEventAndListeningForAnotherEventOnDifferentThread() throws {
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
    func testDefaultThread() throws {
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

    func testReceiveOnMainThread() throws {
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

    func testReceiveOnBackgroundThread() throws {
        // given
        let threadExpectation = expectation(description: "Should receive an event on the background thread")
        eventBus.onReceive(ResetEvent.self, performOn: DispatchQueue.global(qos: .background)) { _ in
            if !Thread.current.isMainThread {
                threadExpectation.fulfill()
            }
        }
        .store(in: &subscriptions)

        // when
        DispatchQueue.main.async {
            self.eventBus.send(ResetEvent())
        }

        // then
        waitForExpectations(timeout: 10)
    }
}

// MARK: - Other

extension EventBusTests {
    func testMultipleSubscribers() throws {
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

    func testNotStoreReferenceWhen() throws {
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

    // MARK: - Replay Logic
}

// MARK: - Mocked data

private extension EventBusTests {
    struct AnotherEvent: EventRepresentable {
        var params: [String: String] = [:]
    }
}
