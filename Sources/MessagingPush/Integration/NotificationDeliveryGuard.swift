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
        var retainedDeliveries: [Delivery] = []
        let liveDeliveries = compactCompletedDeliveriesLocked(retaining: &retainedDeliveries)
        let wasCompleted = liveDeliveries.contains { $0 === delivery }
        let inserted = wasCompleted
            ? false
            : activeIdentifiers.insert(ObjectIdentifier(delivery)).inserted
        lock.unlock()
        withExtendedLifetime(retainedDeliveries) {}

        return inserted
    }

    func complete(_ delivery: Delivery) {
        lock.lock()
        var retainedDeliveries: [Delivery] = []
        let liveDeliveries = compactCompletedDeliveriesLocked(retaining: &retainedDeliveries)
        if !liveDeliveries.contains(where: { $0 === delivery }) {
            completedDeliveries.append(WeakDelivery(delivery))
        }
        activeIdentifiers.remove(ObjectIdentifier(delivery))
        lock.unlock()
        withExtendedLifetime(retainedDeliveries) {}
    }

    /// Weak loads are retained until after the state lock is released. Otherwise the temporary produced by a
    /// weak load can become an app-owned delivery's last owner and run its `deinit` reentrantly under this lock.
    private func compactCompletedDeliveriesLocked(
        retaining retainedDeliveries: inout [Delivery]
    ) -> [Delivery] {
        var liveDeliveries: [Delivery] = []
        completedDeliveries = completedDeliveries.filter { completedDelivery in
            guard let delivery = completedDelivery.delivery else { return false }
            retainedDeliveries.append(delivery)
            liveDeliveries.append(delivery)
            return true
        }
        return liveDeliveries
    }
}
