import Foundation

/// Coordinates one peer callback for one notification delivery across every Customer.io proxy.
///
/// A public ``CioNotificationCenterDelegate`` can itself be registered as a peer and can wrap another peer that
/// is also registered directly. This guard preserves the public subclass callback while ensuring the wrapped
/// identity is invoked only once across the resulting proxy graph. Completed pairs are retained weakly, so an
/// asynchronous forwarding path using the same delivery is suppressed without retaining either object or
/// deduplicating a later delivery that merely has the same payload.
final class NotificationPeerDeliveryGuard<Delivery: AnyObject>: @unchecked Sendable {
    final class Lease {
        private let lock = NSLock()
        private var onEnd: (() -> Void)?

        init(onEnd: @escaping () -> Void) {
            self.onEnd = onEnd
        }

        func end() {
            lock.lock()
            let callback = onEnd
            onEnd = nil
            lock.unlock()
            callback?()
        }

        deinit {
            end()
        }
    }

    private struct InvocationKey: Hashable {
        let delivery: ObjectIdentifier
        let peer: ObjectIdentifier
    }

    private final class CompletedInvocation {
        weak var delivery: Delivery?
        weak var peer: AnyObject?

        init(delivery: Delivery, peer: AnyObject) {
            self.delivery = delivery
            self.peer = peer
        }
    }

    private let lock = NSLock()
    private var activeInvocations: Set<InvocationKey> = []
    private var completedInvocations: [CompletedInvocation] = []

    func begin(_ delivery: Delivery, peer: AnyObject) -> Lease? {
        let key = InvocationKey(
            delivery: ObjectIdentifier(delivery),
            peer: ObjectIdentifier(peer)
        )

        lock.lock()
        var retainedReferents: [AnyObject] = []
        let completedPairs = compactCompletedInvocationsLocked(retaining: &retainedReferents)
        let wasCompleted = completedPairs.contains {
            $0.delivery === delivery && $0.peer === peer
        }
        let inserted = wasCompleted ? false : activeInvocations.insert(key).inserted
        lock.unlock()
        withExtendedLifetime(retainedReferents) {}

        guard inserted else { return nil }
        return Lease { [weak self, delivery, peer] in
            self?.complete(delivery, peer: peer)
        }
    }

    private func complete(_ delivery: Delivery, peer: AnyObject) {
        let key = InvocationKey(
            delivery: ObjectIdentifier(delivery),
            peer: ObjectIdentifier(peer)
        )

        lock.lock()
        var retainedReferents: [AnyObject] = []
        let completedPairs = compactCompletedInvocationsLocked(retaining: &retainedReferents)
        if !completedPairs.contains(where: {
            $0.delivery === delivery && $0.peer === peer
        }) {
            completedInvocations.append(CompletedInvocation(delivery: delivery, peer: peer))
        }
        activeInvocations.remove(key)
        lock.unlock()
        withExtendedLifetime(retainedReferents) {}
    }

    /// Weak loads are retained until after the state lock is released. Otherwise the temporary produced by a
    /// weak load can become an app peer's last owner and run its `deinit` reentrantly under this lock.
    private func compactCompletedInvocationsLocked(
        retaining retainedReferents: inout [AnyObject]
    ) -> [(delivery: Delivery, peer: AnyObject)] {
        var liveInvocations: [CompletedInvocation] = []
        var livePairs: [(delivery: Delivery, peer: AnyObject)] = []
        for invocation in completedInvocations {
            let delivery = invocation.delivery
            let peer = invocation.peer
            if let delivery {
                retainedReferents.append(delivery)
            }
            if let peer {
                retainedReferents.append(peer)
            }
            if let delivery, let peer {
                liveInvocations.append(invocation)
                livePairs.append((delivery: delivery, peer: peer))
            }
        }
        completedInvocations = liveInvocations
        return livePairs
    }
}
