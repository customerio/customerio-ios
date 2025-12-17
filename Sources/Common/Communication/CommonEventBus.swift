//
//  CommonEventBus.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/17/25.
//

import Foundation

public final class CommonEventBus: @unchecked Sendable, Autoresolvable {
    
    private final class EventBusRegistrationToken: RegistrationToken, @unchecked Sendable {
        
        private weak var eventBus: CommonEventBus?
        public private(set) var identifier: UUID
        
        init(eventBus: CommonEventBus, identifier: UUID = UUID()) {
            self.eventBus = eventBus
            self.identifier = identifier
        }
        
        deinit {
            guard let eventBus else {
                return
            }
            eventBus.removeRegistration(for: identifier)
        }
    }
    
    private class NotifyOperation: Operation, @unchecked Sendable {
        var wasHandled: Bool? = nil
        
        let event: any Sendable
        let listener: (any Sendable) -> Bool
        init(event: any Sendable, listener: @escaping (any Sendable) -> Bool) {
            self.event = event
            self.listener = listener
        }
        override func main() {
            wasHandled = listener(event)
        }
    }
    
    private let syncQueue = DispatchQueue(label: "io.customer.sdk.CommonEventBus.syncQueue", attributes: .concurrent)
    private let notifiyQueue = OperationQueue()
    
    private var observers: [UUID: (Any) -> Bool] = [:]
    
    private let logger: Logger
    
    public init(logger: Logger) {
        self.logger = logger
    }
    
    public init(resolver: Resolver) throws {
        logger = try resolver.resolve()
    }
    
    public func registerObserver<EventType: Sendable>(listener: @escaping (EventType) -> Void) -> RegistrationToken {
        let token = EventBusRegistrationToken(eventBus: self)
        syncQueue.sync(flags: .barrier) {
            self.observers[token.identifier] = { untypedEvent in
                guard let event = untypedEvent as? EventType else {
                    return false
                }
                listener(event)
                return true
            }
            self.logger.debug("Registration complete for events of type \(String(describing: EventType.self)) and assigned identifier \(token.identifier.uuidString).")
            
        }
        return token
    }
    
    private func removeRegistration(for identifier: UUID) {
        // This happens ASYNC to not risk stalling the thread due to a deinit
        syncQueue.async(flags: .barrier) {
            self.observers.removeValue(forKey: identifier)
            self.logger.debug("Registration removed for identifier \(identifier).")
        }
    }
    
    public func post(_ event: any Sendable) {
        let eventTypeName = String(describing: type(of: event))
        let arrivalTime = Date()
        self.logger.debug("Beginning post for event of type \(eventTypeName)")
        // Fetch the observers synchronously now in case they change before enqueuing the callbacks
        let observers = syncQueue.sync {
            self.observers.values
        }
        guard !observers.isEmpty else {
            self.logger.debug("No observers are registered for any events, so aborting delivery.")
            return
            
        }
        // Notifications delivery queuing happens in the background
        Task {
            let ops = observers.map { NotifyOperation(event: event, listener: $0) }
            
            // Don't post delivery summaries for delivery summaries
            if !(event is EventDeliverySummary) {
                let sendSummaryOperation = BlockOperation { [weak self] in
                    guard let self else { return }
                    self.logger.debug("Preparing delivery summary for delivery of event of type \(eventTypeName)")
                    let completionTime = Date()
                    let handledCount = ops.count { op in
                        op.wasHandled ?? false
                    }
                    let summary = EventDeliverySummary(
                        sourceEvent: event,
                        registeredObservers: ops.count,
                        handlingObservers: handledCount,
                        arrivalTime: arrivalTime,
                        completionTime: completionTime
                    )
                    self.post(summary)
                    self.logger.debug("Submitted delivery summary for delivery of event of type \(eventTypeName)")
                }
                ops.forEach {
                    sendSummaryOperation.addDependency($0)
                }
                self.notifiyQueue.addOperation(sendSummaryOperation)
            }
            ops.forEach {
                self.notifiyQueue.addOperation($0)
            }
            self.logger.debug("Completed queuing post for event of type \(eventTypeName) to \(observers.count) potential listeners.")
        }
    }
    
    public func postAndWait(_ event: any Sendable) async -> EventDeliverySummary {
        let arrivalTime = Date()
        let eventTypeName = String(describing: type(of: event))
        self.logger.debug("Beginning postAndWait for event of type \(eventTypeName)")
        
        // Fetch the observers synchronously now in case they change before enqueuing the callbacks
        let observers = syncQueue.sync {
            self.observers.values
        }
        
        return await withCheckedContinuation { continuation in
            var handledEvents: Int = 0
            for observer in observers {
                handledEvents += observer(event) ? 1 : 0
            }
            let summary = EventDeliverySummary(
                sourceEvent: event,
                registeredObservers: observers.count,
                handlingObservers: handledEvents,
                arrivalTime: arrivalTime,
                completionTime: Date()
            )
            self.logger.debug("Completing postAndWait for event of type \(eventTypeName) with \(handledEvents) handled events.")
            continuation.resume(returning: summary)
        }
    }
}
