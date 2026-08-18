import Foundation

/// Prevents one notification-center delivery object from restarting the same proxy fan-out.
///
/// Active delivery identities stay guarded until the completion aggregate finishes or is abandoned. Completed
/// objects are remembered weakly, so a peer that forwards the exact same object after completion is suppressed
/// without retaining deliveries or deduplicating a later delivery that only has the same payload.
final class NotificationDeliveryGuard<Delivery: AnyObject>: @unchecked Sendable {
    private final class WeakDelivery {
        weak var delivery: Delivery?

        init(_ delivery: Delivery) {
            self.delivery = delivery
        }
    }

    private let lock = NSLock()
    private var activeIdentifiers: Set<ObjectIdentifier> = []
    private var completedDeliveries: [WeakDelivery] = []

    func begin(_ delivery: Delivery) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        completedDeliveries.removeAll { $0.delivery == nil }
        guard !completedDeliveries.contains(where: { $0.delivery === delivery }) else { return false }

        let identifier = ObjectIdentifier(delivery)
        guard activeIdentifiers.insert(identifier).inserted else { return false }
        return true
    }

    func complete(_ delivery: Delivery) {
        lock.lock()
        completedDeliveries.removeAll { $0.delivery == nil }
        if !completedDeliveries.contains(where: { $0.delivery === delivery }) {
            completedDeliveries.append(WeakDelivery(delivery))
        }
        activeIdentifiers.remove(ObjectIdentifier(delivery))
        lock.unlock()
    }
}
