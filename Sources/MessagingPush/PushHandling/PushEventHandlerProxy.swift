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
    /*
     # Why is this class not stored in the digraph?

     Similar to why the SDK's `UNUserNotificationCenterDelegate` instance is also not in the digraph. See those comments to learn more.
     */
    public static let shared = PushEventHandlerProxyImpl()

    // Use a map so that we only save 1 instance of a given handler.
    @Atomic private var nestedDelegates: [String: PushEventHandler] = [:]

    func addPushEventHandler(_ newHandler: PushEventHandler) {
        nestedDelegates[String(describing: newHandler)] = newHandler
    }

    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void) {
        let nestedDelegates = self.nestedDelegates // create a scoped copy for this function body.

        // If there are no other click handlers, then call the completion handler. Indicating that the CIO SDK handled it.
        guard !nestedDelegates.isEmpty else {
            completionHandler()
            return
        }

        Task {
            // Wait for all other push event handlers to finish before calling the completion handler.
            // Each iteration of the loop waits for the push event to be processed by the delegate.
            for delegate in nestedDelegates.values {
                await withCheckedContinuation { continuation in
                    delegate.onPushAction(pushAction) {
                        continuation.resume()
                    }
                }
            }
            // After the loop finishes, call the completion handler to indicate the event has been fully processed by all delegates.
            completionHandler()
        }
    }

    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (Bool) -> Void) {
        let nestedDelegates = self.nestedDelegates // create a scoped copy for this function body.

        // If there are no other click handlers, then call the completion handler. Indicating that the CIO SDK handled it.
        guard !nestedDelegates.isEmpty else {
            completionHandler(true)
            return
        }

        Task {
            // 2+ other push event handlers may exist in app. We need to decide if a push should be displayed or not, by combining all the results from all other push handlers.
            // To do that, we start with Apple's default value of: do not display.
            // If any of the handlers return result indicating push should be displayed, we return true.
            // Apple docs: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)
            var shouldDisplayPush = false

            // Wait for all other push event handlers to finish before calling the completion handler.
            // Each iteration of the loop waits for the push event to be processed by the delegate.
            for delegate in nestedDelegates.values {
                await withCheckedContinuation { continuation in
                    delegate.shouldDisplayPushAppInForeground(push, completionHandler: { delegateShouldDisplayPushResult in
                        if delegateShouldDisplayPushResult {
                            shouldDisplayPush = true
                        }

                        continuation.resume()
                    })
                }
            }
            // After the loop finishes, call the completion handler to indicate the event has been fully processed by all delegates.
            completionHandler(shouldDisplayPush)
        }
    }
}

// Manually add a getter in the digraph.
// We must use this manual approach instead of auto generated code because the class maintains its own singleton instance outside of the digraph.
// This getter allows convenient access to this dependency via the digraph.
extension DIGraph {
    @available(iOSApplicationExtension, unavailable)
    var pushEventHandlerProxy: PushEventHandlerProxy {
        PushEventHandlerProxyImpl.shared
    }
}
