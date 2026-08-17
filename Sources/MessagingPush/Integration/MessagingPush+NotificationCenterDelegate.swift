import CioInternalCommon
import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
private enum ProxyInstallOutcome {
    case alreadyInstalled
    case installed
    case reasserted
    case deferredToOutermostSetter
    case notInstalled(displacedBy: String)

    var isInstalledOrDeferred: Bool {
        switch self {
        case .alreadyInstalled, .installed, .reasserted, .deferredToOutermostSetter:
            return true
        case .notInstalled:
            return false
        }
    }

    /// Reports only interference that helps customers diagnose another delegate-setter swizzler. Normal and
    /// nested successful installation paths stay quiet because peer registration already has debug logging.
    func log(logger: Logger) {
        switch self {
        case .alreadyInstalled, .installed, .deferredToOutermostSetter:
            break
        case .reasserted:
            logger.info("CIO: Reinstalled the Customer.io notification delegate after another setter changed it during installation.")
        case .notInstalled(let displacedBy):
            logger.error("CIO: Could not keep the Customer.io notification delegate installed after another setter replaced it with \(displacedBy). Push-open handling may be incomplete. Check notification delegate swizzling order.")
        }
    }
}

@available(iOSApplicationExtension, unavailable)
extension MessagingPush {
    var installedNotificationCenterDelegate: CioNotificationCenterDelegate? {
        notificationCenterDelegate as? CioNotificationCenterDelegate
    }

    /// Installs the SDK proxy for the first time, preserving the delegate currently assigned to the center.
    ///
    /// The setter swizzle is activated before reading `center.delegate`, and the read and registry mutation are
    /// serialized with every intercepted later assignment. Therefore the captured delegate cannot become a
    /// stale value that is registered after a newer delegate or `nil` assignment.
    static func installNotificationCenterDelegate(
        centerProvider: UserNotificationCenterInstance
    ) {
        let logger = DIGraphShared.shared.logger
        var center = centerProvider()

        installLock.lock()
        beginSwizzlingDelegateSetter()
        let wrappedDelegate = center.delegate
        let preparedInstallation = prepareNotificationCenterDelegateInstallationLocked(
            wrapping: wrappedDelegate
        )
        installLock.unlock()

        finishNotificationCenterDelegateInstallation(
            preparedInstallation,
            wrapping: wrappedDelegate,
            on: &center,
            logger: logger
        )
    }

    /// Records an assignment intercepted by the swizzled delegate setter and keeps the SDK proxy installed.
    /// Both this path and the first-install path reuse one process-wide proxy retained by `MessagingPush`.
    /// `wrappedDelegate` semantics, including duplicate identity and `nil` clearing, are defined by
    /// ``NotificationDelegatePeerRegistry/register(_:)``.
    @discardableResult
    static func installNotificationCenterDelegate(
        wrapping wrappedDelegate: UNUserNotificationCenterDelegate?,
        centerProvider: UserNotificationCenterInstance
    ) -> Bool {
        let logger = DIGraphShared.shared.logger
        var center = centerProvider()

        installLock.lock()
        beginSwizzlingDelegateSetter()
        let preparedInstallation = prepareNotificationCenterDelegateInstallationLocked(
            wrapping: wrappedDelegate
        )
        installLock.unlock()

        return finishNotificationCenterDelegateInstallation(
            preparedInstallation,
            wrapping: wrappedDelegate,
            on: &center,
            logger: logger
        )
    }

    /// Creates or reuses the shared proxy and registers one assignment.
    /// Must be called with ``installLock`` held.
    private static func prepareNotificationCenterDelegateInstallationLocked(
        wrapping wrappedDelegate: UNUserNotificationCenterDelegate?
    ) -> (
        proxy: CioNotificationCenterDelegate,
        registration: NotificationDelegateRegistrationOutcome?
    ) {
        let proxy: CioNotificationCenterDelegate
        if let installedProxy = shared.installedNotificationCenterDelegate {
            proxy = installedProxy
        } else {
            proxy = CioNotificationCenterDelegate(
                messagingPush: shared,
                config: { moduleConfig },
                peerRegistry: NotificationDelegatePeerRegistryImpl()
            )
            shared.notificationCenterDelegate = proxy
        }

        // Ignore only this exact installed proxy. A separately constructed public CioNotificationCenterDelegate
        // is an external peer and must be preserved like any other app-owned delegate.
        let registrationOutcome: NotificationDelegateRegistrationOutcome?
        if wrappedDelegate === proxy {
            registrationOutcome = nil
        } else {
            registrationOutcome = proxy.peerRegistry.register(wrappedDelegate)
        }

        return (proxy: proxy, registration: registrationOutcome)
    }

    /// Completes installation without holding ``installLock``. Setter calls can enter earlier swizzlers and
    /// logger dispatchers can invoke app code, so both actions deliberately happen outside the transaction.
    private static func finishNotificationCenterDelegateInstallation(
        _ installation: (
            proxy: CioNotificationCenterDelegate,
            registration: NotificationDelegateRegistrationOutcome?
        ),
        wrapping wrappedDelegate: UNUserNotificationCenterDelegate?,
        on center: inout UserNotificationCenterIntegration,
        logger: Logger
    ) -> Bool {
        let proxyInstallationOutcome = ensureNotificationCenterDelegateInstalled(
            installation.proxy,
            on: &center
        )

        installation.registration?.log(peer: wrappedDelegate, logger: logger)
        proxyInstallationOutcome.log(logger: logger)
        return proxyInstallationOutcome.isInstalledOrDeferred
    }

    /// Assigns the proxy and verifies what the getter reports after every earlier setter swizzler has returned.
    ///
    /// A swizzler may synchronously assign or substitute its own delegate. The first post-set mismatch is
    /// followed by one reassertion after that setter chain has fully unwound. If the same chain displaces the
    /// proxy again, repeating it cannot produce new information and risks unbounded recursion, so the SDK emits
    /// an actionable error instead of guessing a timeout or retry count.
    private static func ensureNotificationCenterDelegateInstalled(
        _ proxy: CioNotificationCenterDelegate,
        on center: inout UserNotificationCenterIntegration
    ) -> ProxyInstallOutcome {
        let threadDictionary = Thread.current.threadDictionary
        if threadDictionary[proxyInstallationThreadKey] as? Bool == true {
            return .deferredToOutermostSetter
        }

        if center.delegate === proxy {
            return .alreadyInstalled
        }

        threadDictionary[proxyInstallationThreadKey] = true
        defer { threadDictionary.removeObject(forKey: proxyInstallationThreadKey) }

        center.delegate = proxy
        guard center.delegate !== proxy else { return .installed }

        center.delegate = proxy
        let delegateAfterReassertion = center.delegate
        if delegateAfterReassertion === proxy { return .reasserted }
        guard let displacedDelegate = delegateAfterReassertion else {
            return .notInstalled(displacedBy: "nil")
        }

        return .notInstalled(displacedBy: String(describing: type(of: displacedDelegate)))
    }

    /// Swizzles `UNUserNotificationCenter.delegate` setter so that any future assignment routes through
    /// `cio_swizzled_setDelegate`, which registers non-CIO delegates as peers rather than displacing the SDK.
    /// The guard ensures the exchange happens exactly once; a second exchange would undo the first.
    ///
    /// Must be called with ``installLock`` held, so that concurrent installs cannot both pass the guard. Only
    /// Objective-C runtime functions run here, never app code, so holding the lock is safe.
    private static func beginSwizzlingDelegateSetter() {
        guard !delegateSetterSwizzled else { return }
        delegateSetterSwizzled = true

        let originalSelector = #selector(setter: UNUserNotificationCenter.delegate)
        let swizzledSelector = #selector(UNUserNotificationCenter.cio_swizzled_setDelegate(delegate:))

        guard
            let originalMethod = class_getInstanceMethod(UNUserNotificationCenter.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(UNUserNotificationCenter.self, swizzledSelector)
        else { return }

        let didAdd = class_addMethod(
            UNUserNotificationCenter.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        if didAdd {
            class_replaceMethod(
                UNUserNotificationCenter.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}
