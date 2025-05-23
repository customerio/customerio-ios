import FirebaseCore
import FirebaseMessaging
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// sourcery: AutoMockable
@available(iOSApplicationExtension, unavailable)
protocol FCMAutoFetchDeviceToken {
    func setup()
}

protocol MessagingIntegration {
    var apnsToken: Data? { get set }
    func token(completion: @escaping (String?, (any Error)?) -> Void)
}

extension Messaging: MessagingIntegration {}

@available(iOSApplicationExtension, unavailable)
class FCMAutoFetchDeviceTokenImpl: FCMAutoFetchDeviceToken {
    private static var didSwizzle: Bool = false
    private let messaging: () -> MessagingIntegration
    private let messagingPushFCM: MessagingPushFCMInstance
    private let appDelegate: () -> UIApplicationDelegate?
    private let registerForRemoteNotification: () -> Void

    init(
        messaging: @escaping () -> MessagingIntegration,
        messagingPushFCM: MessagingPushFCMInstance,
        appDelegate: @escaping () -> UIApplicationDelegate?,
        registerForRemoteNotification: @escaping () -> Void
    ) {
        self.messaging = messaging
        self.messagingPushFCM = messagingPushFCM
        self.appDelegate = appDelegate
        self.registerForRemoteNotification = registerForRemoteNotification
    }

    func setup() {
        guard !Self.didSwizzle else {
            return
        }

        Self.didSwizzle = true

        guard let appDelegate = appDelegate() else {
            return
        }

        swizzleDidRegisterForRemoteNotifications(appDelegate: appDelegate)
        swizzleDidFailToRegisterForRemoteNofifications(appDelegate: appDelegate)

        registerForRemoteNotification()
    }

    private func swizzleDidRegisterForRemoteNotifications(appDelegate: UIApplicationDelegate) {
        guard let appDelegateClass = object_getClass(appDelegate) else {
            return
        }

        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: FCMAutoFetchDeviceTokenImpl.self, original: originalSelector, new: swizzledSelector)
    }

    private func swizzleDidFailToRegisterForRemoteNofifications(appDelegate: UIApplicationDelegate) {
        guard let appDelegateClass = object_getClass(appDelegate) else {
            return
        }

        let originalSelectorForDidFail = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let swizzledSelectorForDidFail = #selector(application(_:didFailToRegisterForRemoteNotificationsWithError:))
        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: FCMAutoFetchDeviceTokenImpl.self, original: originalSelectorForDidFail, new: swizzledSelectorForDidFail)
    }

    private func swizzle(forOriginalClass: AnyClass?, forSwizzledClass: AnyClass?, original: Selector, new: Selector) {
        guard let swizzledMethod = class_getInstanceMethod(forSwizzledClass, new) else { return }
        guard let originalMethod = class_getInstanceMethod(forOriginalClass, original) else {
            // Add method if it doesn't exist
            class_addMethod(forOriginalClass, new, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    // Swizzled method for APN device token.
    // Fetch the FCM token using the Firebase delegate method when the APN token is set.
    @objc
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        var messagingInstance = messaging()
        messagingInstance.apnsToken = deviceToken
        // Registers listener with FCM SDK to always have the latest FCM token.
        // Used to automatically register it with the SDK.
        messagingInstance.token(completion: { [weak self] token, _ in
            guard let token = token else {
                return
            }
            self?.messagingPushFCM.registerDeviceToken(fcmToken: token)
        })
    }

    // Swizzled method for `didFailToRegisterForRemoteNotificationsWithError'
    @objc
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        messagingPushFCM.deleteDeviceToken()
    }
}
