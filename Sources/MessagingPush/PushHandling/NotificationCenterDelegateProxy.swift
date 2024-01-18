import CioInternalCommon
import Foundation

protocol NotificationCenterDelegateProxy: AutoMockable {
    func addPushEventHandler(_ newHandler: PushEventHandler)
    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void)
    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (Bool) -> Void)
}

/*
 Because the CIO SDK forces itself to be the app's only push click handler, we want our SDK to still be compatible with other SDKs that also need to handle pushes being clicked.

 This class is a proxy that forwards requests to all other click handlers that have been registered with the app. Including 3rd party SDKs.
 */
class NotificationCenterDelegateProxyImpl: NotificationCenterDelegateProxy {
    public static let shared = NotificationCenterDelegateProxyImpl()

    // Use a map so that we only save 1 instance of a given Delegate.
    private var nestedDelegates: [String: PushEventHandler] = [:]

    func addPushEventHandler(_ newHandler: PushEventHandler) {
        // TODO: this line below seems fragile. If we change the class name, this could break.
        // could digraph inject instance of the SDK's intance before setting singleton?
        let doesDelegateBelongToCio = newHandler is iOSPushEventListener

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

    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (Bool) -> Void) {
        nestedDelegates.forEach { _, delegate in
            delegate.shouldDisplayPushAppInForeground(push, completionHandler: completionHandler)
        }
    }
}
