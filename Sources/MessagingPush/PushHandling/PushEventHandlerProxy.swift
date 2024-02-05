import CioInternalCommon
import Foundation

// Forwards requests from our SDK to other push event handlers in the host iOS app, if our SDK does not handle the push event.
@available(iOSApplicationExtension, unavailable)
protocol PushEventHandlerProxy: AutoMockable {
    func addPushEventHandler(_ newHandler: PushEventHandler)

    // When these push event handler functions are called, the request is forwarded to other push handlers.
    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void)
    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (Bool) -> Void)
}

/*
 Because the CIO SDK forces itself to be the app's only push click handler, we want our SDK to still be compatible with other SDKs that also need to handle pushes being clicked.

 This class is a proxy that forwards requests to all other click handlers that have been registered with the app. Including 3rd party SDKs.
 */
@available(iOSApplicationExtension, unavailable)
class PushEventHandlerProxyImpl: PushEventHandlerProxy {
    public static let shared = PushEventHandlerProxyImpl()

    // Use a map so that we only save 1 instance of a given handler.
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
