import CioInternalCommon
import UIKit
import UserNotifications

/// The single `UNUserNotificationCenterDelegate` the SDK installs on `UNUserNotificationCenter`.
///
/// `UNUserNotificationCenter.delegate` holds one delegate, weakly, and every assignment replaces the previous
/// one. To stay in the notification pipeline, exactly one instance of this class is
/// created, retained by `MessagingPush`, and installed as the system delegate; every other delegate the app or
/// another SDK assigns is kept as a *peer* in ``peerRegistry`` and receives forwarded callbacks. Peers assigned
/// before `MessagingPush.initialize()` and peers assigned after it are treated identically. The registry stores
/// peers weakly and compacts released entries on every read and registration. It does not evict live peers:
/// silently dropping an app or SDK delegate would break notification delivery for that integration.
///
/// Per delivery, the delegate takes one strongly retained snapshot of the live peers, calls each directly
/// registered peer identity at most once, and answers the system's completion handler exactly once after every
/// peer has reported. See
/// ``PeerDeliveryCompletionAggregate`` for the completion rules and ``NotificationDelegatePeerRegistry``
/// for the storage and ownership rules.
@available(iOSApplicationExtension, unavailable)
open class CioNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Preserve the initializer's ownership contract. The shared instance has process lifetime; compatibility
    // callers that provide another implementation continue to have it retained for the delegate's lifetime.
    private let messagingPush: MessagingPushInstance
    private let config: ConfigInstance?
    private let handlePushResponse: (UNUserNotificationCenter, UNNotificationResponse) -> Void
    private let systemDelegate: (UNUserNotificationCenter) -> UNUserNotificationCenterDelegate?
    /// Keeps a forwarded response alive for as long as its nesting count is active. Retaining the object, rather
    /// than only its address, prevents a later response from reusing the same `ObjectIdentifier` after an
    /// asynchronous peer abandons its completion.
    private struct ForwardedPeerInvocation {
        let response: UNNotificationResponse
        var count: Int
    }

    /// Tracks responses dispatched to this instance as a peer of another Customer.io proxy. The response stays
    /// marked through its completion, preserving the no-duplicate rule when a subclass calls `super`
    /// asynchronously while still allowing its public override to be invoked dynamically.
    private let forwardedPeerLock = NSLock()
    private var forwardedPeerInvocations: [ObjectIdentifier: ForwardedPeerInvocation] = [:]
    /// Customer.io processing is process-wide even when an opaque third-party wrapper reaches another public
    /// Customer.io delegate transitively. Per-proxy guards still own each proxy's forwarding graph.
    private static let customerIOResponseGuard = NotificationDeliveryGuard<UNNotificationResponse>()
    private let didReceiveDeliveryGuard = NotificationDeliveryGuard<UNNotificationResponse>()
    private let openSettingsDeliveryGuard = NotificationDeliveryGuard<UNNotification>()
    private let willPresentDeliveryGuard = NotificationDeliveryGuard<UNNotification>()
    private let nilOpenSettingsLock = NSLock()
    private var deliveredNilOpenSettingsSinceBackground = false
    private var applicationBackgroundObserver: NSObjectProtocol?
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
        self.systemDelegate = { $0.delegate }
        self.compatibilityWrappedDelegate = wrappedDelegate
        // This public compatibility initializer has no logger dependency. Shared graph resolution stays at the
        // top-level module installer, which injects a logged registry through the internal initializer.
        self.peerRegistry = NotificationDelegatePeerRegistryImpl()
        super.init()

        peerRegistry.register(wrappedDelegate)
        observeApplicationBackground()
    }

    init(
        messagingPush: MessagingPushInstance,
        config: ConfigInstance?,
        peerRegistry: NotificationDelegatePeerRegistry,
        handlePushResponse: ((UNUserNotificationCenter, UNNotificationResponse) -> Void)? = nil,
        systemDelegate: @escaping (UNUserNotificationCenter) -> UNUserNotificationCenterDelegate? = { $0.delegate }
    ) {
        self.messagingPush = messagingPush
        self.config = config
        self.peerRegistry = peerRegistry
        self.handlePushResponse = handlePushResponse ?? Self.makePushResponseHandler(messagingPush: messagingPush)
        self.systemDelegate = systemDelegate
        self.compatibilityWrappedDelegate = nil
        super.init()
        observeApplicationBackground()
    }

    deinit {
        if let applicationBackgroundObserver {
            NotificationCenter.default.removeObserver(applicationBackgroundObserver)
        }
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
        guard willPresentDeliveryGuard.begin(notification) else {
            // A peer is forwarding this same delivery back into the proxy. Resolve the nested request with
            // Customer.io's configured fallback, just as this proxy would with no implementing peer. The
            // configured policy may legitimately be an empty option set.
            completionHandler(cioConfiguredPresentationOptions)
            return
        }

        // Preserve the existing single-peer contract: when at least one peer implements this selector, the
        // result comes only from peers. With several implementing peers their options are unioned, rather than
        // using last-writer-wins. Customer.io's configured default is the fallback only when there are no
        // implementing peers.
        let peers = peersResponding(
            on: center,
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))
        )
        let aggregate = PeerDeliveryCompletionAggregate<UNNotificationPresentationOptions>(
            retaining: peers.map { $0 as AnyObject },
            deliveryObject: notification,
            initialValue: peers.isEmpty ? cioConfiguredPresentationOptions : [],
            merge: { $0.union($1) },
            onFinished: { [weak self] options in
                self?.willPresentDeliveryGuard.complete(notification)
                completionHandler(options)
            },
            onAbandoned: { [weak self] in
                self?.willPresentDeliveryGuard.complete(notification)
            }
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
        guard didReceiveDeliveryGuard.begin(response) else {
            // The outer invocation already performed Customer.io handling and owns the peer aggregate.
            completionHandler()
            return
        }

        let peers = peersResponding(
            on: center,
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
        )
        // Snapshot before Customer.io processing, which may synchronously route into app code that assigns a
        // delegate. Such a reentrant peer begins with the next delivery, just like assignment from another peer.
        let shouldHandleCustomerIO = !isForwardedPeerInvocation(response)
            && Self.customerIOResponseGuard.begin(response)
        if shouldHandleCustomerIO {
            handlePushResponse(center, response)
        }
        let releaseDeliveryGuards = { [weak self] in
            if shouldHandleCustomerIO {
                Self.customerIOResponseGuard.complete(response)
            }
            self?.didReceiveDeliveryGuard.complete(response)
        }
        let aggregate = PeerDeliveryCompletionAggregate<Void>(
            retaining: peers.map { $0 as AnyObject },
            deliveryObject: response,
            initialValue: (),
            merge: { _, _ in () },
            onFinished: { _ in
                releaseDeliveryGuards()
                completionHandler()
            },
            onAbandoned: releaseDeliveryGuards
        )

        for (token, peer) in peers.enumerated() {
            let peerCompletion = {
                aggregate.complete(token: token, with: ())
            }
            if let cioPeer = peer as? CioNotificationCenterDelegate {
                cioPeer.invokeAsForwardingPeer(
                    center,
                    didReceive: response,
                    withCompletionHandler: peerCompletion
                )
            } else {
                peer.userNotificationCenter?(
                    center,
                    didReceive: response,
                    withCompletionHandler: peerCompletion
                )
            }
        }

        aggregate.finishDispatching()
    }

    /// Prevent issues caused by swizzling in various SDKs that check for method existence without using
    /// `responds(to:)` (e.g. FirebaseMessaging). An empty stub ensures the method exists for forwarding.
    ///
    /// There is no completion handler to aggregate here, so every live peer that implements it is simply called
    /// once, in registration order.
    open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        guard beginOpenSettingsDelivery(notification) else { return }
        defer { completeOpenSettingsDelivery(notification) }

        let peers = peersResponding(
            on: center,
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
    private func peersResponding(
        on center: UNUserNotificationCenter,
        to selector: Selector
    ) -> [UNUserNotificationCenterDelegate] {
        let installedSystemDelegate = systemDelegate(center)
        let respondingPeers = peerRegistry.livePeers().filter {
            // An earlier setter swizzler may keep its own forwarding proxy installed above Customer.io's proxy.
            // That object has already received this system callback and is now forwarding it to us. Calling it
            // again as a peer would create a delegate cycle, so exclude only the exact installed object.
            $0 !== installedSystemDelegate && $0.responds(to: selector)
        }

        // A public Customer.io compatibility delegate may itself wrap a peer that was assigned earlier. Keep
        // only the outer delegate in this fan-out so its normal forwarding reaches the wrapped peer once rather
        // than calling the wrapped peer both directly and transitively. Opaque third-party proxies cannot expose
        // this relationship; their installed-system identity is handled by the exclusion above.
        let transitivelyForwardedIdentities = Set(
            respondingPeers.compactMap { peer -> CioNotificationCenterDelegate? in
                guard let cioPeer = peer as? CioNotificationCenterDelegate,
                      type(of: cioPeer) == CioNotificationCenterDelegate.self else {
                    return nil
                }
                return cioPeer
            }
            .flatMap { $0.directForwardingPeerIdentities(respondingTo: selector) }
        )
        return respondingPeers.filter {
            !transitivelyForwardedIdentities.contains(ObjectIdentifier($0))
        }
    }

    /// Calls this instance through its public, dynamically dispatched delegate method while marking the call
    /// as forwarding from another Customer.io proxy. A public `CioNotificationCenterDelegate` can legitimately
    /// be installed by an app and later become a peer of the process-wide proxy. Calling it normally would run
    /// Customer.io opened handling twice. Calling the dynamic method in this context preserves subclass
    /// customization and that instance's wrapped-delegate fan-out while its `super` implementation skips only
    /// the duplicate Customer.io handling. The response remains marked until the peer completes, so an override
    /// may call `super` asynchronously without losing that context.
    private func invokeAsForwardingPeer(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        beginForwardedPeerInvocation(response)

        userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: { [weak self] in
                self?.endForwardedPeerInvocation(response)
                completionHandler()
            }
        )
    }

    private func beginForwardedPeerInvocation(_ response: UNNotificationResponse) {
        let identifier = ObjectIdentifier(response)
        forwardedPeerLock.lock()
        if var invocation = forwardedPeerInvocations[identifier], invocation.response === response {
            invocation.count += 1
            forwardedPeerInvocations[identifier] = invocation
        } else {
            forwardedPeerInvocations[identifier] = ForwardedPeerInvocation(response: response, count: 1)
        }
        forwardedPeerLock.unlock()
    }

    private func endForwardedPeerInvocation(_ response: UNNotificationResponse) {
        let identifier = ObjectIdentifier(response)
        forwardedPeerLock.lock()
        let remainingCount = (forwardedPeerInvocations[identifier]?.count ?? 1) - 1
        if remainingCount > 0, var invocation = forwardedPeerInvocations[identifier] {
            invocation.count = remainingCount
            forwardedPeerInvocations[identifier] = invocation
        } else {
            forwardedPeerInvocations.removeValue(forKey: identifier)
        }
        forwardedPeerLock.unlock()
    }

    private func isForwardedPeerInvocation(_ response: UNNotificationResponse) -> Bool {
        forwardedPeerLock.lock()
        let invocation = forwardedPeerInvocations[ObjectIdentifier(response)]
        let isForwarded = invocation?.response === response && (invocation?.count ?? 0) > 0
        forwardedPeerLock.unlock()
        return isForwarded
    }

    private func observeApplicationBackground() {
        applicationBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            nilOpenSettingsLock.lock()
            deliveredNilOpenSettingsSinceBackground = false
            nilOpenSettingsLock.unlock()
        }
    }
}

@available(iOSApplicationExtension, unavailable)
private extension CioNotificationCenterDelegate {
    /// Direct peer identities this compatibility delegate will forward `selector` to when invoked.
    func directForwardingPeerIdentities(respondingTo selector: Selector) -> [ObjectIdentifier] {
        peerRegistry.livePeers()
            .filter { $0.responds(to: selector) }
            .map(ObjectIdentifier.init)
    }

    func beginOpenSettingsDelivery(_ notification: UNNotification?) -> Bool {
        guard let notification = notification else {
            // Apple supplies nil only when Settings opens the app without a notification object. With no
            // delivery identity to propagate, retain one marker for the foreground epoch so an asynchronously
            // forwarding delegate cannot create an unbounded cycle. Entering background starts the next real
            // Settings activation epoch.
            nilOpenSettingsLock.lock()
            defer { nilOpenSettingsLock.unlock() }
            guard !deliveredNilOpenSettingsSinceBackground else { return false }
            deliveredNilOpenSettingsSinceBackground = true
            return true
        }
        return openSettingsDeliveryGuard.begin(notification)
    }

    func completeOpenSettingsDelivery(_ notification: UNNotification?) {
        guard let notification else { return }
        openSettingsDeliveryGuard.complete(notification)
    }

    /// Adapts the concrete-only push response function once at construction.
    static func makePushResponseHandler(
        messagingPush: MessagingPushInstance
    ) -> (UNUserNotificationCenter, UNNotificationResponse) -> Void {
        guard let messagingPush = messagingPush as? MessagingPush else { return { _, _ in } }
        return { [weak messagingPush] center, response in
            _ = messagingPush?.userNotificationCenter(center, didReceive: response)
        }
    }
}
