import UIKit
import UserNotifications

/// Coordinates peer delivery across every Customer.io notification delegate in the process.
final class NotificationPeerDeliveryCoordinator {
    /// Keeps a forwarded response alive while its nesting count is active. Retaining the object, rather than
    /// only its address, prevents a later response from reusing the same `ObjectIdentifier`.
    private struct ForwardedPeerInvocation {
        let response: UNNotificationResponse
        var count: Int
    }

    /// Owns one forwarding marker until the peer completes or abandons the supplied completion closure.
    final class ForwardedPeerInvocationLease {
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

    private static let willPresentGuard = NotificationPeerDeliveryGuard<UNNotification>()
    private static let didReceiveGuard = NotificationPeerDeliveryGuard<UNNotificationResponse>()
    private static let openSettingsGuard = NotificationPeerDeliveryGuard<UNNotification>()
    private static let nilOpenSettingsDelegateGuard = NotificationPeerDeliveryGuard<NSObject>()
    private static let nilOpenSettingsPeerGuard = NotificationPeerDeliveryGuard<NSObject>()
    private static let nilOpenSettingsActivationLock = NSLock()
    private static var nilOpenSettingsActivation = NSObject()
    private static let applicationActivationObserver = ApplicationActivationObserver()

    private let forwardedPeerLock = NSLock()
    private var forwardedPeerInvocations: [ObjectIdentifier: ForwardedPeerInvocation] = [:]

    func beginWillPresent(
        _ notification: UNNotification,
        peer: UNUserNotificationCenterDelegate
    ) -> NotificationPeerDeliveryGuard<UNNotification>.Lease? {
        Self.willPresentGuard.begin(notification, peer: peer)
    }

    func beginDidReceive(
        _ response: UNNotificationResponse,
        peer: UNUserNotificationCenterDelegate
    ) -> NotificationPeerDeliveryGuard<UNNotificationResponse>.Lease? {
        Self.didReceiveGuard.begin(response, peer: peer)
    }

    func beginOpenSettings(
        _ notification: UNNotification?,
        peer: UNUserNotificationCenterDelegate
    ) -> NotificationPeerDeliveryGuard<UNNotification>.Lease? {
        guard let notification else { return nil }
        return Self.openSettingsGuard.begin(notification, peer: peer)
    }

    func beginNilOpenSettings(
        peer: UNUserNotificationCenterDelegate
    ) -> NotificationPeerDeliveryGuard<NSObject>.Lease? {
        Self.beginNilOpenSettings(using: Self.nilOpenSettingsPeerGuard, peer: peer)
    }

    func beginNilOpenSettingsDelivery(
        delegate: UNUserNotificationCenterDelegate
    ) -> NotificationPeerDeliveryGuard<NSObject>.Lease? {
        Self.beginNilOpenSettings(using: Self.nilOpenSettingsDelegateGuard, peer: delegate)
    }

    static func startObservingApplicationActivation() {
        applicationActivationObserver.start {
            resetNilOpenSettingsActivation()
        }
    }

    private static func beginNilOpenSettings(
        using deliveryGuard: NotificationPeerDeliveryGuard<NSObject>,
        peer: UNUserNotificationCenterDelegate
    ) -> NotificationPeerDeliveryGuard<NSObject>.Lease? {
        while true {
            nilOpenSettingsActivationLock.lock()
            let activation = nilOpenSettingsActivation
            nilOpenSettingsActivationLock.unlock()

            let lease = deliveryGuard.begin(activation, peer: peer)

            nilOpenSettingsActivationLock.lock()
            let activationIsCurrent = nilOpenSettingsActivation === activation
            nilOpenSettingsActivationLock.unlock()
            if activationIsCurrent {
                return lease
            }

            // A foreground transition won the race. Retire the old-generation lease outside the activation
            // lock, then retry against the new generation. No app-owned weak referent is released under the
            // activation lock or the guard's state lock.
            lease?.end()
        }
    }

    private static func resetNilOpenSettingsActivation() {
        nilOpenSettingsActivationLock.lock()
        nilOpenSettingsActivation = NSObject()
        nilOpenSettingsActivationLock.unlock()
    }

    func beginForwardedPeerInvocation(
        _ response: UNNotificationResponse
    ) -> ForwardedPeerInvocationLease {
        let identifier = ObjectIdentifier(response)
        forwardedPeerLock.lock()
        if var invocation = forwardedPeerInvocations[identifier], invocation.response === response {
            invocation.count += 1
            forwardedPeerInvocations[identifier] = invocation
        } else {
            forwardedPeerInvocations[identifier] = ForwardedPeerInvocation(response: response, count: 1)
        }
        forwardedPeerLock.unlock()
        return ForwardedPeerInvocationLease { [weak self, response] in
            self?.endForwardedPeerInvocation(response)
        }
    }

    func isForwardedPeerInvocation(_ response: UNNotificationResponse) -> Bool {
        forwardedPeerLock.lock()
        let invocation = forwardedPeerInvocations[ObjectIdentifier(response)]
        let isForwarded = invocation?.response === response && (invocation?.count ?? 0) > 0
        forwardedPeerLock.unlock()
        return isForwarded
    }

    var activeForwardedPeerInvocationsCount: Int {
        forwardedPeerLock.lock()
        let count = forwardedPeerInvocations.count
        forwardedPeerLock.unlock()
        return count
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
}
