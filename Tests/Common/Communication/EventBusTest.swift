@testable import CioInternalCommon
import SharedTests
import XCTest

class SharedEventBusTests: UnitTest {
    var eventBus: SharedEventBus!
    var notificationReceived: Bool!

    override func setUp() {
        super.setUp()
        eventBus = SharedEventBus()
        notificationReceived = false
    }

    override func tearDown() {
        eventBus = nil
        super.tearDown()
    }

    func testPostEventWithObserver() {
        let exp = expectation(description: "Event received")
        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            self.notificationReceived = true
            exp.fulfill()
        }

        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event)

        waitForExpectations(timeout: 1)
        XCTAssertTrue(notificationReceived)
    }

    func testPostEventWithoutObserver() {
        let event = ProfileIdentifiedEvent(identifier: "123")
        let hasObservers = eventBus.post(event)
        XCTAssertFalse(hasObservers)
    }

    func testMultipleObserversForSameEvent() {
        let exp1 = expectation(description: "First observer received event")
        let exp2 = expectation(description: "Second observer received event")

        var firstObserverNotified = false
        var secondObserverNotified = false

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            firstObserverNotified = true
            exp1.fulfill()
        }

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            secondObserverNotified = true
            exp2.fulfill()
        }

        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event)

        waitForExpectations(timeout: 1)
        XCTAssertTrue(firstObserverNotified, "First observer should receive the event")
        XCTAssertTrue(secondObserverNotified, "Second observer should receive the event")
    }

    func testObserversForDifferentEventTypes() {
        let exp1 = expectation(description: "Observer for event type 1 receives event")
        let exp2 = expectation(description: "Observer for event type 2 receives event")

        var observer1Notified = false
        var observer2Notified = false

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            observer1Notified = true
            exp1.fulfill()
        }

        eventBus.addObserver(ScreenViewedEvent.key) { _ in
            observer2Notified = true
            exp2.fulfill()
        }

        let event1 = ProfileIdentifiedEvent(identifier: "123")
        let event2 = ScreenViewedEvent(name: "ABC")

        eventBus.post(event1)
        eventBus.post(event2)

        waitForExpectations(timeout: 1)
        XCTAssertTrue(observer1Notified, "Observer for ProfileIdentifiedEvent should be notified")
        XCTAssertTrue(observer2Notified, "Observer for ScreenViewedEvent should be notified")
    }

    func testMultipleObserversForSameEventType() {
        let exp1 = expectation(description: "First observer receives event")
        let exp2 = expectation(description: "Second observer receives event")

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in exp1.fulfill() }
        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in exp2.fulfill() }

        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event)

        waitForExpectations(timeout: 1)
    }

    func testRemovingSpecificObserver() {
        let exp = expectation(description: "Event received")
        exp.isInverted = true

        // Add and immediately remove the observer
        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            exp.fulfill()
        }
        eventBus.removeObserver(for: ProfileIdentifiedEvent.key)

        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event)

        // Expectation should not be fulfilled as observer has been removed
        waitForExpectations(timeout: 1)
        XCTAssertFalse(notificationReceived, "Observer should not receive the event after being removed")
    }

    func testObserverReceivingMultipleNotifications() {
        let exp = expectation(description: "Observer receives multiple events")
        exp.expectedFulfillmentCount = 2

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in exp.fulfill() }

        let event1 = ProfileIdentifiedEvent(identifier: "123")
        let event2 = ProfileIdentifiedEvent(identifier: "456")
        eventBus.post(event1)
        eventBus.post(event2)

        waitForExpectations(timeout: 1)
    }

    func testRemovingAllObservers() {
        let exp = expectation(description: "Event received")
        exp.isInverted = true

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            exp.fulfill()
        }

        eventBus.removeAllObservers()
        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event)

        waitForExpectations(timeout: 1)
        XCTAssertFalse(notificationReceived, "No observers should receive the event after removing all")
    }

    func testPostEventOnSpecificQueue() {
        let exp = expectation(description: "Event received on specific queue")
        let queue = DispatchQueue(label: "test.queue")
        let key = DispatchSpecificKey<String>()
        queue.setSpecific(key: key, value: "test.queue")

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in
            if DispatchQueue.getSpecific(key: key) == "test.queue" {
                exp.fulfill()
            } else {
                XCTFail("Notification should be received on the specified queue")
            }
        }

        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event, on: queue)

        waitForExpectations(timeout: 1)
    }

    func testObserverNotNotifiedAfterRemoval() {
        let exp = expectation(description: "Observer should not receive event")
        exp.isInverted = true

        eventBus.addObserver(ProfileIdentifiedEvent.key) { _ in exp.fulfill() }
        eventBus.removeObserver(for: ProfileIdentifiedEvent.key)

        let event = ProfileIdentifiedEvent(identifier: "123")
        eventBus.post(event)

        waitForExpectations(timeout: 1)
    }
}
