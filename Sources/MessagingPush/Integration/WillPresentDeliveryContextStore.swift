import Foundation
import UserNotifications

/// Stores the identity and peer count for each active `willPresent` delivery.
///
/// Retaining the notification prevents `ObjectIdentifier` reuse while an asynchronous peer owns the delivery.
/// The peer count lets a nested forwarding cycle preserve the single-peer fallback without leaking that fallback
/// into a multi-peer result.
@available(iOSApplicationExtension, unavailable)
final class WillPresentDeliveryContextStore {
    private struct Context {
        let notification: UNNotification
        let peerCount: Int
    }

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

    func remove(_ notification: UNNotification) {
        lock.lock()
        let identifier = ObjectIdentifier(notification)
        if contexts[identifier]?.notification === notification {
            contexts.removeValue(forKey: identifier)
        }
        lock.unlock()
    }
}

@available(iOSApplicationExtension, unavailable)
extension CioNotificationCenterDelegate {
    /// Direct peer identities this compatibility delegate will forward `selector` to when invoked.
    func directForwardingPeerIdentities(respondingTo selector: Selector) -> [ObjectIdentifier] {
        peerRegistry.livePeers()
            .filter { $0.responds(to: selector) }
            .map(ObjectIdentifier.init)
    }
}
