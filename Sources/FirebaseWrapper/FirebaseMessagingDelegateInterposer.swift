import Foundation

/// Sits in Firebase's `Messaging.delegate` slot without taking it from the app.
///
/// The delegate the app had already set becomes the downstream and keeps receiving every callback: the two registration
/// callbacks are forwarded explicitly, anything else through `forwardingTarget(for:)`. This is Firebase's supported way to
/// learn about new registrations; its token-refresh notification is deprecated in Firebase 13.
/// If the app sets its own delegate later, it replaces the interposer, and the adapter falls back to the notification.
final class FirebaseMessagingDelegateInterposer: NSObject {
    static let didReceiveRegistrationTokenSelector = NSSelectorFromString("messaging:didReceiveRegistrationToken:")
    static let didReceiveRegistrationSelector = NSSelectorFromString("messaging:didReceiveRegistration:")

    /// The delegate the app set before the interposer, held weakly like Firebase holds its delegate.
    weak var downstream: NSObject?

    // Called with the registration and whether it is an FID (`true`) or an FCM token (`false`).
    private let onRegistration: (String?, Bool) -> Void

    init(onRegistration: @escaping (String?, Bool) -> Void) {
        self.onRegistration = onRegistration
    }

    @objc(messaging:didReceiveRegistrationToken:)
    func messaging(_ messaging: NSObject, didReceiveRegistrationToken token: String?) {
        onRegistration(token, false)
        forward(Self.didReceiveRegistrationTokenSelector, messaging, token)
    }

    @objc(messaging:didReceiveRegistration:)
    func messaging(_ messaging: NSObject, didReceiveRegistration installationId: String?) {
        onRegistration(installationId, true)
        forward(Self.didReceiveRegistrationSelector, messaging, installationId)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || downstream?.responds(to: aSelector) == true
    }

    // Other MessagingDelegate callbacks, such as `messaging:didUnregister:` in Firebase 13, go to the app's delegate.
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let downstream = downstream, downstream.responds(to: aSelector) {
            return downstream
        }
        return super.forwardingTarget(for: aSelector)
    }

    private func forward(_ selector: Selector, _ messaging: NSObject, _ registration: String?) {
        // Strong only while forwarding, in case the callback releases the app's delegate.
        guard let downstream = downstream, downstream.responds(to: selector) else { return }
        _ = downstream.perform(selector, with: messaging, with: registration as NSString?)
    }
}
