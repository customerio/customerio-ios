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
// sourcery: InjectRegisterShared = "PushEventHandlerProxy"
// sourcery: InjectSingleton
class PushEventHandlerProxyImpl: PushEventHandlerProxy {
    // Use a map so that we only save 1 instance of a given handler.
    @Atomic var nestedDelegates: [String: PushEventHandler] = [:]

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func addPushEventHandler(_ newHandler: PushEventHandler) {
        nestedDelegates[newHandler.identifier] = newHandler
    }

    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void) {
        let nestedDelegates = self.nestedDelegates // create a scoped copy for this function body.

        // If there are no other click handlers, then call the completion handler. Indicating that the CIO SDK handled it.
        guard !nestedDelegates.isEmpty else {
            completionHandler()
            return
        }

        // UserNotification runs this event on the main thread.
        // Run this async task on the main thread to match that behavior. Otherwise, we run the risk of warnings or crashes by trying to call UIKit
        // functions from a background thread.
        Task { @MainActor in
            // Wait for all other push event handlers to finish before calling the completion handler.
            // Each iteration of the loop waits for the push event to be processed by the delegate.
            for delegate in nestedDelegates.values {
                await withCheckedContinuation { continuation in
                    // Some SDKs, like the rn-firebase SDK (RNFBMessagingUNUserNotificationCenter), will call the completionHandler twice.
                    // Handle that by only responding to the first call and ignoring the rest.
                    var hasResumed = false

                    let nameOfDelegateClass: String = .init(describing: delegate)

                    // Using logs to give feedback to customer if 1 or more delegates do not call the async completion handler.
                    // These logs could help in debuggging to determine what delegate did not call the completion handler.
                    self.logger.info("Sending push notification, \(pushAction.push.title), action event to: \(nameOfDelegateClass)). Customer.io SDK will wait for async completion handler to be called...")

                    delegate.onPushAction(pushAction) {
                        Task { @MainActor in // in case the delegate calls the completion handler on a background thread, we need to switch back to the main thread.
                            self.logger.info("Received async completion handler from \(nameOfDelegateClass) for action push event.")

                            if !hasResumed {
                                hasResumed = true

                                continuation.resume()
                            }
                        }
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

        // UserNotification runs this event on the main thread.
        // Run this async task on the main thread to match that behavior. Otherwise, we run the risk of warnings or crashes by trying to call UIKit
        // functions from a background thread.
        Task { @MainActor in
            // 2+ other push event handlers may exist in app. We need to decide if a push should be displayed or not, by combining all the results from all other push handlers.
            // To do that, we start with Apple's default value of: do not display.
            // If any of the handlers return result indicating push should be displayed, we return true.
            // Apple docs: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)
            var shouldDisplayPush = false

            // Wait for all other push event handlers to finish before calling the completion handler.
            // Each iteration of the loop waits for the push event to be processed by the delegate.
            for delegate in nestedDelegates.values {
                await withCheckedContinuation { continuation in
                    // Some SDKs, like the rn-firebase SDK (RNFBMessagingUNUserNotificationCenter), will call the completionHandler twice.
                    // Handle that by only responding to the first call and ignoring the rest.
                    var hasResumed = false

                    let nameOfDelegateClass: String = .init(describing: delegate)

                    // Using logs to give feedback to customer if 1 or more delegates do not call the async completion handler.
                    // These logs could help in debuggging to determine what delegate did not call the completion handler.
                    self.logger.info("Sending push notification, \(push.title), will display event to: \(nameOfDelegateClass)). Customer.io SDK will wait for async completion handler to be called...")

                    delegate.shouldDisplayPushAppInForeground(push, completionHandler: { delegateShouldDisplayPushResult in
                        Task { @MainActor in // in case the delegate calls the completion handler on a background thread, we need to switch back to the main thread.
                            self.logger.info("Received async completion handler from \(nameOfDelegateClass) for will display event.")

                            if !hasResumed {
                                hasResumed = true

                                if delegateShouldDisplayPushResult {
                                    shouldDisplayPush = true
                                }

                                continuation.resume()
                            }
                        }
                    })
                }
            }
            // After the loop finishes, call the completion handler to indicate the event has been fully processed by all delegates.
            completionHandler(shouldDisplayPush)
        }
    }
}
