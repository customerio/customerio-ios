import Foundation
import Testing

@testable import CustomerIO_Utilities

// MARK: - Helpers

private struct PingEvent: Sendable { let value: Int }
private struct OtherEvent: Sendable { let label: String }

// MARK: - Test Suite

@Suite struct EventBusTests {

    // MARK: - Basic delivery

    @Test func postDeliveredToObserver() async {
        let bus = CommonEventBus()
        let received: Synchronized<[Int]> = Synchronized([])
        let token = bus.registerObserver { (event: PingEvent) in
            received.append(event.value)
        }

        let summary = await bus.postAndWait(PingEvent(value: 42))
        _ = token  // keep token alive

        #expect(summary.handlingObservers == 1)
        #expect(received.wrappedValue == [42])
    }

    @Test func postNotDeliveredToWrongType() async {
        let bus = CommonEventBus()
        let received: Synchronized<[String]> = Synchronized([])
        let token = bus.registerObserver { (event: OtherEvent) in
            received.append(event.label)
        }

        let summary = await bus.postAndWait(PingEvent(value: 1))
        _ = token

        // The observer registered for OtherEvent should not handle PingEvent
        #expect(summary.handlingObservers == 0)
        #expect(received.isEmpty)
    }

    // MARK: - Multiple observers

    @Test func multipleObserversAllReceive() async {
        let bus = CommonEventBus()
        let count: Synchronized<Int> = Synchronized(0)

        let t1 = bus.registerObserver { (_: PingEvent) in count += 1 }
        let t2 = bus.registerObserver { (_: PingEvent) in count += 1 }
        let t3 = bus.registerObserver { (_: PingEvent) in count += 1 }

        let summary = await bus.postAndWait(PingEvent(value: 0))
        _ = (t1, t2, t3)

        #expect(summary.registeredObservers == 3)
        #expect(summary.handlingObservers == 3)
        #expect(count.wrappedValue == 3)
    }

    // MARK: - Token deregistration

    @Test func observerDeregisteredWhenTokenReleased() async {
        let bus = CommonEventBus()
        let received: Synchronized<Int> = Synchronized(0)

        var token: RegistrationToken<UUID>? = bus.registerObserver { (_: PingEvent) in
            received.wrappedValue = 1
        }
        // Release token → observer should unregister
        token = nil

        let summary = await bus.postAndWait(PingEvent(value: 7))
        _ = token

        #expect(summary.registeredObservers == 0)
        #expect(received.wrappedValue == 0)
    }

    @Test func retainedTokenKeepsObserverAlive() async {
        let bus = CommonEventBus()
        let called: Synchronized<Bool> = Synchronized(false)

        let token = bus.registerObserver { (_: PingEvent) in
            called.wrappedValue = true
        }

        let summary = await bus.postAndWait(PingEvent(value: 1))
        _ = token

        #expect(called.wrappedValue)
        #expect(summary.handlingObservers == 1)
    }

    // MARK: - DeliverySummary shape

    @Test func deliverySummaryTimestampsOrdered() async {
        let bus = CommonEventBus()
        let t = bus.registerObserver { (_: PingEvent) in }
        let summary = await bus.postAndWait(PingEvent(value: 0))
        _ = t
        #expect(summary.completionTime >= summary.arrivalTime)
    }

    // MARK: - RegistrationToken

    @Test func registrationTokenExposesIdentifier() {
        let called = Synchronized(false)
        let token = RegistrationToken(identifier: UUID()) { called.wrappedValue = true }
        let id = token.identifier
        // Identifier is accessible and is a UUID
        #expect(id == id)
        withExtendedLifetime(token) {}
    }

    @Test func registrationTokenCallsActionOnDeinit() {
        let called: Synchronized<Bool> = Synchronized(false)
        do {
            let token = RegistrationToken(identifier: UUID()) {
                called.wrappedValue = true
            }
            #expect(!called.wrappedValue)
            _ = token
        }
        #expect(called.wrappedValue)
    }
}
