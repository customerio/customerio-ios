import CioInternalCommon
import UIKit
import UserNotifications

/// The single `UNUserNotificationCenterDelegate` the SDK installs on `UNUserNotificationCenter`.
///
/// `UNUserNotificationCenter.delegate` holds one delegate, weakly, and every assignment replaces the previous
/// one. To stay in the notification pipeline, exactly one instance of this class is
/// created, retained by `MessagingPush`, and installed as the system delegate; every other delegate the app or
/// another SDK assigns is kept as a *peer* in ``peerRegistry`` and receives forwarded callbacks. Peers assigned
/// before `MessagingPush.initialize()` and peers assigned after it are treated identically. Composition is
/// deliberately bounded to eight live peers; after dead entries are compacted, the oldest live peer is evicted
/// if a ninth distinct peer is assigned.
///
/// Per delivery, the delegate takes one strongly retained snapshot of the live peers, calls each peer at most
/// once, and answers the system's completion handler exactly once after every peer has reported. See
/// ``PeerDeliveryCompletionAggregate`` for the completion rules and ``NotificationDelegatePeerRegistry``
/// for the storage and ownership rules.
@available(iOSApplicationExtension, unavailable)
open class CioNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Preserve the initializer's ownership contract. The shared instance has process lifetime; compatibility
    // callers that provide another implementation continue to have it retained for the delegate's lifetime.
    private let messagingPush: MessagingPushInstance
    private let config: ConfigInstance?
    private let handlePushResponse: (UNUserNotificationCenter, UNNotificationResponse) -> Void
    /// Preserves the public initializer's existing strong ownership of its single wrapped delegate. The
    /// process-wide internal proxy leaves this nil and keeps its multi-peer registry weak.
    private let compatibilityWrappedDelegate: UNUserNotificationCenterDelegate?

    /// The external delegates that forwarded callbacks are fanned out to.
    let peerRegistry: NotificationDelegatePeerRegistry

    /// Creates a delegate that forwards to `wrappedDelegate` in addition to Customer.io's own handling.
    ///
    /// Kept for API compatibility. Prefer ``init(messagingPush:config:peerRegistry:)`` inside the SDK so that
    /// the registry is injected rather than resolved from the shared dependency graph.
    public init(
        messagingPush: MessagingPushInstance,
        config: ConfigInstance?,
        wrappedDelegate: UNUserNotificationCenterDelegate?
    ) {
        self.messagingPush = messagingPush
        self.config = config
        self.handlePushResponse = Self.makePushResponseHandler(messagingPush: messagingPush)
        self.compatibilityWrappedDelegate = wrappedDelegate
        // This public compatibility initializer has no logger dependency. Shared graph resolution stays at the
        // top-level module installer, which injects a logged registry through the internal initializer.
        self.peerRegistry = NotificationDelegatePeerRegistryImpl()
        super.init()

        peerRegistry.register(wrappedDelegate)
    }

    init(
        messagingPush: MessagingPushInstance,
        config: ConfigInstance?,
        peerRegistry: NotificationDelegatePeerRegistry,
        handlePushResponse: ((UNUserNotificationCenter, UNNotificationResponse) -> Void)? = nil
    ) {
        self.messagingPush = messagingPush
        self.config = config
        self.peerRegistry = peerRegistry
        self.handlePushResponse = handlePushResponse ?? Self.makePushResponseHandler(messagingPush: messagingPush)
        self.compatibilityWrappedDelegate = nil
        super.init()
    }

    /// The presentation options Customer.io uses only when no live peer implements `willPresent`.
    private var cioConfiguredPresentationOptions: UNNotificationPresentationOptions {
        guard config?().showPushAppInForeground ?? false else { return [] }

        if #available(iOS 14.0, *) {
            return [.list, .banner, .badge, .sound]
        } else {
            return [.alert, .badge, .sound]
        }
    }

    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Preserve the existing single-peer contract: when at least one peer implements this selector, the
        // result comes only from peers. With several implementing peers their options are unioned, rather than
        // using last-writer-wins. Customer.io's configured default is the fallback only when there are no
        // implementing peers.
        let peers = peersResponding(
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))
        )
        let aggregate = PeerDeliveryCompletionAggregate<UNNotificationPresentationOptions>(
            retaining: peers.map { $0 as AnyObject },
            initialValue: peers.isEmpty ? cioConfiguredPresentationOptions : [],
            merge: { $0.union($1) },
            onFinished: completionHandler
        )

        for (token, peer) in peers.enumerated() {
            peer.userNotificationCenter?(
                center,
                willPresent: notification,
                withCompletionHandler: { options in
                    aggregate.complete(token: token, with: options)
                }
            )
        }

        aggregate.finishDispatching()
    }

    // Function called when a push notification is clicked or swiped away.
    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let peers = peersResponding(
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
        )
        // Snapshot before Customer.io processing, which may synchronously route into app code that assigns a
        // delegate. Such a reentrant peer begins with the next delivery, just like assignment from another peer.
        handlePushResponse(center, response)
        let aggregate = PeerDeliveryCompletionAggregate<Void>(
            retaining: peers.map { $0 as AnyObject },
            initialValue: (),
            merge: { _, _ in () },
            onFinished: { _ in completionHandler() }
        )

        for (token, peer) in peers.enumerated() {
            peer.userNotificationCenter?(
                center,
                didReceive: response,
                withCompletionHandler: {
                    aggregate.complete(token: token, with: ())
                }
            )
        }

        aggregate.finishDispatching()
    }

    /// Prevent issues caused by swizzling in various SDKs that check for method existence without using
    /// `responds(to:)` (e.g. FirebaseMessaging). An empty stub ensures the method exists for forwarding.
    ///
    /// There is no completion handler to aggregate here, so every live peer that implements it is simply called
    /// once, in registration order.
    open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        let peers = peersResponding(
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))
        )

        for peer in peers {
            peer.userNotificationCenter?(center, openSettingsFor: notification)
        }
    }

    /// One strongly retained snapshot of the peers that implement `selector`, in registration order.
    ///
    /// Taken once at the start of a delivery and used for that whole delivery. That keeps the fan-out stable: a
    /// peer registered while the delivery is in flight — including one a peer assigns reentrantly from its own
    /// callback — does not join this delivery. The completion aggregate intentionally retains this exact snapshot
    /// until the one outer completion returns, so an asynchronous peer cannot disappear part-way through an
    /// active delivery. The weak registry does not retain it beyond that delivery.
    private func peersResponding(to selector: Selector) -> [UNUserNotificationCenterDelegate] {
        peerRegistry.livePeers().filter { $0.responds(to: selector) }
    }

    /// Adapts the concrete-only push response function once at construction. Keeping this closure injectable
    /// makes the proxy's exactly-once Customer.io processing independently testable without widening the public
    /// `MessagingPushInstance` protocol with an app-only API.
    private static func makePushResponseHandler(
        messagingPush: MessagingPushInstance
    ) -> (UNUserNotificationCenter, UNNotificationResponse) -> Void {
        guard let messagingPush = messagingPush as? MessagingPush else { return { _, _ in } }
        return { [weak messagingPush] center, response in
            _ = messagingPush?.userNotificationCenter(center, didReceive: response)
        }
    }
}
