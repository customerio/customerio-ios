import Foundation
import UserNotifications

/// Tracks active `willPresent` deliveries and synchronous peer callbacks that forward into a cycle.
///
/// Retaining the notification prevents `ObjectIdentifier` reuse while an asynchronous peer owns the delivery.
/// A thread-local invocation ties a nested completion to the peer it can answer without changing the options
/// visible to the peer. Callbacks that leave that synchronous scope are treated as independent decisions.
@available(iOSApplicationExtension, unavailable)
final class WillPresentDeliveryContextStore {
    private struct Context {
        let notification: UNNotification
        let peerCount: Int
    }

    private final class PeerInvocation {
        let store: ObjectIdentifier
        let notification: ObjectIdentifier
        let token: Int
        let previous: PeerInvocation?
        var isCompletingCycle = false
        var receivedCycleResponse = false

        init(store: ObjectIdentifier, notification: ObjectIdentifier, token: Int, previous: PeerInvocation?) {
            self.store = store
            self.notification = notification
            self.token = token
            self.previous = previous
        }
    }

    private static let peerInvocationKey = "io.customer.messagingPush.willPresentPeerInvocation"
    private let lock = NSLock()
    private var contexts: [ObjectIdentifier: Context] = [:]

    func remember(_ notification: UNNotification, peerCount: Int) {
        lock.lock()
        contexts[ObjectIdentifier(notification)] = Context(
            notification: notification,
            peerCount: peerCount
        )
        lock.unlock()
    }

    func isSolePeerDelivery(_ notification: UNNotification) -> Bool {
        lock.lock()
        let context = contexts[ObjectIdentifier(notification)]
        let isSolePeerDelivery = context?.notification === notification && context?.peerCount == 1
        lock.unlock()
        return isSolePeerDelivery
    }

    func invokePeer(for notification: UNNotification, token: Int, _ invoke: () -> Void) -> Bool {
        let threadDictionary = Thread.current.threadDictionary
        let previous = threadDictionary[Self.peerInvocationKey] as? PeerInvocation
        let invocation = PeerInvocation(
            store: ObjectIdentifier(self),
            notification: ObjectIdentifier(notification),
            token: token,
            previous: previous
        )
        threadDictionary[Self.peerInvocationKey] = invocation
        defer { threadDictionary[Self.peerInvocationKey] = previous }
        invoke()
        return invocation.receivedCycleResponse
    }

    /// Marks only the nested completion call. The peer can still provide its own options after it returns.
    func withCycleCompletion(for notification: UNNotification, _ complete: () -> Void) {
        let invocation = peerInvocation(for: notification)
        let wasCompletingCycle = invocation?.isCompletingCycle ?? false
        invocation?.isCompletingCycle = true
        defer { invocation?.isCompletingCycle = wasCompletingCycle }
        complete()
    }

    func recordCycleResponse(for notification: UNNotification, token: Int) -> Bool {
        guard let invocation = peerInvocation(for: notification),
              invocation.token == token, invocation.isCompletingCycle else { return false }
        invocation.receivedCycleResponse = true
        return true
    }

    func remove(_ notification: UNNotification) {
        lock.lock()
        let identifier = ObjectIdentifier(notification)
        if contexts[identifier]?.notification === notification {
            contexts.removeValue(forKey: identifier)
        }
        lock.unlock()
    }

    private func peerInvocation(for notification: UNNotification) -> PeerInvocation? {
        let store = ObjectIdentifier(self)
        let notification = ObjectIdentifier(notification)
        var invocation = Thread.current.threadDictionary[Self.peerInvocationKey] as? PeerInvocation
        while let current = invocation {
            if current.store == store, current.notification == notification {
                return current
            }
            invocation = current.previous
        }
        return nil
    }
}
