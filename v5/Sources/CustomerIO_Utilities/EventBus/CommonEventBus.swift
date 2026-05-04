import Foundation

public protocol EventBus: Sendable {
    func registerObserver<EventType: Sendable>(listener: @Sendable @escaping (EventType) -> Void)
        -> RegistrationToken<UUID>
    func post(_ event: any Sendable)
}

public final class CommonEventBus: Sendable, EventBus {

    private final class NotifyOperation: Operation, @unchecked Sendable {
        let wasHandled: Synchronized<Bool?> = .init(nil)

        let event: any Sendable
        let listener: @Sendable (any Sendable) -> Bool
        init(event: any Sendable, listener: @Sendable @escaping (any Sendable) -> Bool) {
            self.event = event
            self.listener = listener
        }
        override func main() {
            wasHandled.wrappedValue = listener(event)
        }
    }

    /// Protocol to classify system messages.
    public protocol SystemMessage: Sendable {}

    /// A summary of the delivery statistics for an event submitted to the event queue.
    public struct DeliverySummary: Sendable, SystemMessage {
        public var sourceEvent: any Sendable
        public var registeredObservers: Int
        public var handlingObservers: Int
        public var arrivalTime: Date
        public var completionTime: Date
    }

    /// A system message dispatched on the EventBus when a new observer registers.
    public struct ObserverAddedMessage: Sendable, SystemMessage {
        public var handledType: Any.Type
        public var listener: @Sendable (Any) -> Bool
    }

    private let notifiyQueue = OperationQueue()
    private let observers: Synchronized<[UUID: @Sendable (Any) -> Bool]> = Synchronized([:])

    public init() {}

    public func registerObserver<EventType: Sendable>(
        listener: @Sendable @escaping (EventType) -> Void
    ) -> RegistrationToken<UUID> {
        let identifier = UUID()
        let token = RegistrationToken(identifier: identifier) { [weak self] in
            guard let self else { return }
            removeRegistration(for: identifier)
        }
        let wrappedListener: @Sendable (Any) -> Bool = { untypedEvent in
            guard let event = untypedEvent as? EventType else { return false }
            listener(event)
            return true
        }
        observers[token.identifier] = wrappedListener
        post(ObserverAddedMessage(handledType: EventType.self, listener: wrappedListener))
        return token
    }

    private func removeRegistration(for identifier: UUID) {
        observers.removeValue(forKey: identifier)
    }

    public func post(_ event: any Sendable) {
        let arrivalTime = Date()
        let snapshot = observers.wrappedValue.values
        guard !snapshot.isEmpty else { return }

        DispatchQueue.global().async {
            let ops = snapshot.map { NotifyOperation(event: event, listener: $0) }

            if !(event is SystemMessage) {
                let sendSummaryOperation = BlockOperation { [weak self] in
                    guard let self else { return }
                    let completionTime = Date()
                    let handledCount = ops.count { op in op.wasHandled.wrappedValue ?? false }
                    self.post(DeliverySummary(
                        sourceEvent: event,
                        registeredObservers: ops.count,
                        handlingObservers: handledCount,
                        arrivalTime: arrivalTime,
                        completionTime: completionTime
                    ))
                }
                ops.forEach { sendSummaryOperation.addDependency($0) }
                self.notifiyQueue.addOperation(sendSummaryOperation)
            }
            self.notifiyQueue.addOperations(ops, waitUntilFinished: false)
        }
    }

    public func postAndWait(_ event: any Sendable) async -> DeliverySummary {
        let arrivalTime = Date()
        let snapshot = observers.wrappedValue.values

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let ops = snapshot.map { NotifyOperation(event: event, listener: $0) }
                self.notifiyQueue.addOperations(ops, waitUntilFinished: true)
                let completionTime = Date()
                let handledCount = ops.count { op in op.wasHandled.wrappedValue ?? false }
                continuation.resume(returning: DeliverySummary(
                    sourceEvent: event,
                    registeredObservers: ops.count,
                    handlingObservers: handledCount,
                    arrivalTime: arrivalTime,
                    completionTime: completionTime
                ))
            }
        }
    }
}
