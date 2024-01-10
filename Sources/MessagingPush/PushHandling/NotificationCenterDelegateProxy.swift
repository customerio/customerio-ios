import CioInternalCommon
import Foundation
import UserNotifications

protocol NotificationCenterDelegateProxy: AutoMockable {
    func addPushEventHandler(_ newHandler: PushEventHandler)
    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void)
    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
}

/*
 Because the CIO SDK forces itself to be the app's only push click handler, we want our SDK to still be compatible with other SDKs that also need to handle pushes being clicked.

 This class is a proxy that forwards requests to all other click handlers that have been registered with the app. Including 3rd party SDKs.
 */
class NotificationCenterDelegateProxyImpl: NotificationCenterDelegateProxy {
    private static var shared: NotificationCenterDelegateProxyImpl?

    static func getInstance(sdkPushEventHandler: PushEventHandler) -> NotificationCenterDelegateProxy {
        if let existingSingletonInstance = shared {
            return existingSingletonInstance
        }

        let newSingletonInstance = NotificationCenterDelegateProxyImpl(sdkPushEventHandler: sdkPushEventHandler)

        shared = newSingletonInstance

        return newSingletonInstance
    }

    private let sdkPushEventHandler: PushEventHandler

    private init(sdkPushEventHandler: PushEventHandler) {
        self.sdkPushEventHandler = sdkPushEventHandler
    }

    // Use a map so that we only save 1 instance of a given Delegate.
    private var nestedDelegates: [String: PushEventHandler] = [:]

    func addPushEventHandler(_ newHandler: PushEventHandler) {
        let nameOfNewDelegate = String(describing: newHandler)
        let nameOfCioSdkPushEventHandler = String(describing: sdkPushEventHandler)

        let doesDelegateBelongToCio = nameOfNewDelegate == nameOfCioSdkPushEventHandler

        guard !doesDelegateBelongToCio else {
            return
        }

        nestedDelegates[String(describing: newHandler)] = newHandler
    }

    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void) {
        nestedDelegates.forEach { _, delegate in
            delegate.onPushAction(pushAction, completionHandler: completionHandler)
        }
    }

    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nestedDelegates.forEach { _, delegate in
            delegate.shouldDisplayPushAppInForeground(push, completionHandler: completionHandler)
        }
    }
}

extension DIGraph {
    var notificationCenterDelegateProxy: NotificationCenterDelegateProxy {
        NotificationCenterDelegateProxyImpl.getInstance(sdkPushEventHandler: pushEventHandler)
    }
}
