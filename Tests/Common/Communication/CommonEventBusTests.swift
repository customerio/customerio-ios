//
//  CommonEventBusTests.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/17/25.
//

import Testing
import Dispatch
@testable import CioInternalCommon


struct CommonEventBusTests {

    @Test
    func testDeliversSimpleEvent() async throws {
        let logger = StandardLogger(logLevel: .debug)
        let eventBus = CommonEventBus(logger: logger)
        var token: RegistrationToken? = nil
        
        await withCheckedContinuation { continuation in
            token = eventBus.registerObserver { (msg: String) in
                #expect(msg == "String Event")
                continuation.resume()
            }
            eventBus.post("String Event")
        }
        if token == nil {
            Issue.record("Token was released early")
        }
    }

    @Test
    func testDeliversToMultipleListeners() async throws {
        let logger = StandardLogger(logLevel: .debug)
        let eventBus = CommonEventBus(logger: logger)
        
        await confirmation("Simple Event Delivered", expectedCount: 2) { done in
            let first = eventBus.registerObserver { (msg: String) in
                #expect(msg == "String Event")
                done()
            }

            let second = eventBus.registerObserver { (msg: String) in
                #expect(msg == "String Event")
                done()
            }

            eventBus.post("String Event")
            // Must sleep to ensure delivery happens before this closure ends
            try? await Task.sleep(nanoseconds: 100_000)
        }
    }

    @Test
    func testSendsDeliverySummary() async throws {
        let logger = StandardLogger(logLevel: .debug)
        let eventBus = CommonEventBus(logger: logger)
        var token: RegistrationToken? = nil
        let deliveryCount = Synchronized(initial: 0)

        await withCheckedContinuation { continuation in
            token = eventBus.registerObserver { (summary: EventDeliverySummary) in
                #expect(summary.sourceEvent as? String == "String Event")
                #expect(summary.registeredObservers == 2)
                #expect(summary.handlingObservers == 1)
                continuation.resume()
            }
            let stringEventToken = eventBus.registerObserver { (msg: String) in
                #expect(msg == "String Event")
                deliveryCount += 1
            }
            eventBus.post("String Event")
        }

        #expect(deliveryCount.value == 1)
        if token == nil {
            Issue.record("Token was released early")
        }
    }

    @Test
    func testObserverRemoved() async throws {
        let logger = StandardLogger(logLevel: .debug)
        let eventBus = CommonEventBus(logger: logger)
        var token: RegistrationToken? = nil
        let deliveryCount = Synchronized(initial: 0)

        token = eventBus.registerObserver { (msg: String) in
            deliveryCount.mutating { value in
                if value == 0 {
                    #expect(msg == "String Event")
                    value += 1
                } else {
                    Issue.record("Received additional delivery")
                }
            }
        }
        eventBus.post("String Event")

        // Must sleep to ensure delivery happens before next steps
        try? await Task.sleep(nanoseconds: 100_000)
        
        #expect(deliveryCount.value == 1)
        token = nil

        // Must sleep to ensure observer removed
        try? await Task.sleep(nanoseconds: 1_000)

        eventBus.post("String Event")

        // Must sleep to ensure delivery happens before next steps
        try? await Task.sleep(nanoseconds: 100_000)

        #expect(deliveryCount.value == 1)

        if token != nil {
            Issue.record("Token not released")
        }

    }

    
}
