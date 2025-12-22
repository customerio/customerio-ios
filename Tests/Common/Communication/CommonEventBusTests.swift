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
        
        let eventString = "String Event"
        
        let firstCallCount = Synchronized(initial: 0)
        let secondCallCount = Synchronized(initial: 0)
        
        let first = eventBus.registerObserver { (msg: String) in
            #expect(msg == eventString)
            firstCallCount += 1
        }

        let second = eventBus.registerObserver { (msg: String) in
            #expect(msg == eventString)
            secondCallCount += 1
        }

        var summaryToken: RegistrationToken? = nil
        await withCheckedContinuation { continuation in
            summaryToken = eventBus.registerObserver { (summary: EventDeliverySummary) in
                #expect(summary.handlingObservers == 2)
                #expect(summary.registeredObservers == 3)
                #expect(summary.sourceEvent as? String == eventString)
                
                continuation.resume()
            }
            
            eventBus.post(eventString)
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

        #expect(deliveryCount.wrappedValue == 1)
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
            #expect(msg == "String Event")

            deliveryCount += 1
        }
        let firstSummary = await eventBus.postAndWait("String Event")
        #expect(firstSummary.handlingObservers == 1)
        #expect(firstSummary.sourceEvent as? String == "String Event")
        #expect(deliveryCount.wrappedValue == 1)
        
        token = nil


        let secondSummary = await eventBus.postAndWait("String Event")
        #expect(secondSummary.handlingObservers == 0)
        #expect(secondSummary.sourceEvent as? String == "String Event")
        #expect(deliveryCount.wrappedValue == 1)

        if token != nil {
            Issue.record("Token not released")
        }
    }

    
}
