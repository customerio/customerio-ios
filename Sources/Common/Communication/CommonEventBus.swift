//
//  CommonEventBus.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/17/25.
//

import Foundation

/// Protocol to classify system messages.
public protocol EventBusSystemMessage: Sendable { }

/// Extension to add conformance of to `EventBusSystemMessage` to
/// `EventDeliverySystem` for filtering/processing purposes.
extension EventDeliverySummary: EventBusSystemMessage { }

public final class CommonEventBus: Sendable, Autoresolvable {
    
    private final class EventBusRegistrationToken: RegistrationToken, Sendable {
        
        public let identifier: UUID
        private let cleanup: @Sendable () -> Void
        
        init(eventBus: CommonEventBus, identifier: UUID = UUID()) {
            self.identifier = identifier
            cleanup = { [weak eventBus] in
                guard let eventBus else {
                    return
                }
                eventBus.removeRegistration(for: identifier)
            }
        }
        
        deinit {
            cleanup()
        }
    }
    
    private class NotifyOperation: Operation, @unchecked Sendable {
        let wasHandled: Synchronized<Bool?> = .init(initial: nil)
        
        let event: any Sendable
        let listener: (any Sendable) -> Bool
        init(event: any Sendable, listener: @escaping (any Sendable) -> Bool) {
            self.event = event
            self.listener = listener
        }
        override func main() {
            wasHandled.wrappedValue = listener(event)
        }
    }
    
    public struct ObserverAddedMessage: EventBusSystemMessage {
        public var handledType: Any.Type
        public var listener: @Sendable (Any) -> Bool
    }
    
    private let notifiyQueue = OperationQueue()
    
    private let observers: Synchronized<[UUID: (Any) -> Bool]> = Synchronized(initial: [:])
    
    private let logger: Logger
    
    public init(logger: Logger) {
        self.logger = logger
    }
    
    public init(resolver: Resolver) throws {
        logger = try resolver.resolve()
    }
    
    public func registerObserver<EventType: Sendable>(listener: @Sendable @escaping (EventType) -> Void) -> RegistrationToken {
        let token = EventBusRegistrationToken(eventBus: self)
        let wrappedListener: @Sendable (Any) -> Bool = { untypedEvent in
            guard let event = untypedEvent as? EventType else {
                return false
            }
            listener(event)
            return true
        }
        observers.mutating {
            $0[token.identifier] = wrappedListener
        }
        logger.debug("Registration complete for events of type \(String(describing: EventType.self)) and assigned identifier \(token.identifier.uuidString).")
        observers[token.identifier] = wrappedListener
        logger.debug("Registration complete for events of type \(String(describing: EventType.self)) and assigned identifier \(token.identifier.uuidString).")

        post(ObserverAddedMessage(
            handledType: EventType.self,
            listener: wrappedListener
        ))
        return token
    }
    
    private func removeRegistration(for identifier: UUID) {
        // This happens ASYNC to not risk stalling the thread due to a deinit
        observers.mutatingDetatched { value in
            value.removeValue(forKey: identifier)
            self.logger.debug("Registration removed for identifier \(identifier).")
        }
    }
    
    public func post(_ event: any Sendable) {
        let eventTypeName = String(describing: type(of: event))
        let arrivalTime = Date()
        self.logger.debug("Beginning post for event of type \(eventTypeName)")
        // Fetch the observers synchronously now in case they change before enqueuing the callbacks
        let snapshot = observers.wrappedValue.values
        guard !snapshot.isEmpty else {
            self.logger.debug("No observers are registered for any events, so aborting delivery.")
            return
            
        }
        // Notifications delivery queuing happens in the background
        Task {
            let ops = snapshot.map { NotifyOperation(event: event, listener: $0) }
            
            // Don't post delivery summaries for delivery summaries
            if !(event is EventBusSystemMessage) {
                let sendSummaryOperation = BlockOperation { [weak self] in
                    guard let self else { return }
                    self.logger.debug("Preparing delivery summary for delivery of event of type \(eventTypeName)")
                    let completionTime = Date()
                    let handledCount = ops.count { op in
                        op.wasHandled.wrappedValue ?? false
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
            self.logger.debug("Completed queuing post for event of type \(eventTypeName) to \(snapshot.count) potential listeners.")
        }
    }
    
    public func postAndWait(_ event: any Sendable) async -> EventDeliverySummary {
        let arrivalTime = Date()
        let eventTypeName = String(describing: type(of: event))
        self.logger.debug("Beginning postAndWait for event of type \(eventTypeName)")
        
        // Fetch the observers synchronously now in case they change before enqueuing the callbacks
        let snapshot = observers.wrappedValue.values
        
        return await withCheckedContinuation { continuation in
            var handledEvents: Int = 0
            for observer in snapshot {
                handledEvents += observer(event) ? 1 : 0
            }
            let summary = EventDeliverySummary(
                sourceEvent: event,
                registeredObservers: snapshot.count,
                handlingObservers: handledEvents,
                arrivalTime: arrivalTime,
                completionTime: Date()
            )
            self.logger.debug("Completing postAndWait for event of type \(eventTypeName) with \(handledEvents) handled events.")
            continuation.resume(returning: summary)
        }
    }
}
