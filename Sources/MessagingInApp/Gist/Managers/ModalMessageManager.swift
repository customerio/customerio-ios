import Foundation
import UIKit

/// A MessageManager subclass that specifically shows messages in a modal view.
public class ModalMessageManager: BaseMessageManager {
    private var modalViewManager: ModalViewManager?
    var inAppMessageStoreSubscriber: InAppMessageStoreSubscriber?
    private var colorSchemeSubscriber: InAppMessageStoreSubscriber?

    let sizePolicy = ModalSizePolicy()
    private var hasArmedSizePolicy = false

    override init(state: InAppMessageState, message: Message) {
        super.init(state: state, message: message)
        subscribeToInAppMessageState()
        subscribeToColorSchemeChanges()
    }

    deinit {
        unsubscribeFromInAppMessageState()
    }

    // MARK: - Subscription to InAppMessageState

    public func subscribeToInAppMessageState() {
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [self] state in
                let messageState = state.modalMessageState
                switch messageState {
                case .displayed:
                    let colorScheme = MessagingInAppImplementation.currentColorScheme
                    threadUtil.runMain {
                        // Subclasses (Modal or Inline) can show differently
                        self.onMessageDisplayed(colorScheme: colorScheme)
                    }
                case .dismissed, .initial:
                    threadUtil.runMain {
                        // Dismiss the message from subclass
                        self.onMessageDismissed(messageState: messageState)
                    }
                default:
                    break
                }
            }
            self.inAppMessageManager.subscribe(keyPath: \.modalMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    // Show the modal when the message is displayed
    func onMessageDisplayed(colorScheme: ColorScheme = .auto) {
        guard isMessageLoaded else {
            logger.logWithModuleTag(
                "Message not loaded yet. Skipping loadModalMessage for \(currentMessage.describeForLogs).",
                level: .debug
            )
            return
        }

        logger.logWithModuleTag(
            "Displaying modal message: \(currentMessage.describeForLogs)",
            level: .debug
        )

        // Only start judging reported heights once the message is on screen. While it loads the
        // WebView is still detached and legitimately measures zero.
        if !hasArmedSizePolicy {
            hasArmedSizePolicy = true
            sizePolicy.arm()
        }

        // Set lifecycle delegate to handle removeFromSuperview event correctly for modal context
        gistView.lifecycleDelegate = self

        let gistProperties = currentMessage.gistProperties
        modalViewManager = ModalViewManager(
            gistView: gistView,
            position: gistProperties.position,
            overlayColor: gistProperties.overlayColor,
            colorScheme: colorScheme
        )
        // Show the modal with an optional completion
        modalViewManager?.showModalView { [weak self] in
            self?.elapsedTimer.end()
        }
    }

    override func handleSizeChanged(width: CGFloat, height: CGFloat) {
        switch sizePolicy.onHeightReported(height) {
        case .degenerate:
            failCollapsedMessage()

        case .viewportDependent(_, let delta):
            logViewportDependentHeight(delta: delta)
            super.handleSizeChanged(width: width, height: height)

        case .apply:
            super.handleSizeChanged(width: width, height: height)
        }
    }

    /// The message is displayed but collapsed, so it covers the screen and swallows touches without
    /// ever showing anything. Failing it dismisses the overlay and tells the host app why.
    private func failCollapsedMessage() {
        logger.logWithModuleTag(
            "In-app message \(currentMessage.messageId) reported a collapsed height " +
                "(<= \(Int(ModalSizePolicy.degenerateMaxPoints))pt) for \(ModalSizePolicy.sampleCount) " +
                "consecutive updates, so it can never become visible while still blocking the " +
                "screen. Dismissing it. \(Self.viewportHeightHint)",
            level: .error
        )
        inAppMessageManager.dispatch(
            action: .engineAction(action: .messageLoadingFailed(message: currentMessage))
        )
    }

    private func logViewportDependentHeight(delta: CGFloat) {
        logger.logWithModuleTag(
            "In-app message \(currentMessage.messageId) keeps growing by \(delta)pt per update, so " +
                "its height tracks the WebView height instead of its content. It will be clamped " +
                "to the screen and its content may not be positioned as designed. " +
                Self.viewportHeightHint,
            level: .error
        )
    }

    private static let viewportHeightHint =
        "This usually means the message HTML derives its own height from the viewport " +
        "(height: 100vh or height: 100% on html/body). The SDK sizes the WebView to the height " +
        "the message reports, so a viewport based height can never resolve; give the message a " +
        "content driven height instead."

    // Called when the message is dismissed (or reset).
    // Because onMessageDismissed(...) is internal in BaseMessageManager,
    // we can override it here in the same module.
    func onMessageDismissed(messageState: ModalMessageState) {
        logger.logWithModuleTag(
            "Dismissing message: \(currentMessage.describeForLogs) from ModalMessageManager",
            level: .debug
        )

        // Common handler to finalize dismissal logic
        let dismissalHandler: () -> Void = { [weak self] in
            self?.finishDismissal(messageState: messageState)
        }

        guard let modalViewManager = modalViewManager else {
            // No modal to dismiss
            dismissalHandler()
            return
        }
        // Dismiss the modal then call completion
        modalViewManager.dismissModalView(completionHandler: dismissalHandler)
    }

    private func subscribeToColorSchemeChanges() {
        colorSchemeSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] _ in
                guard let self else { return }
                let colorScheme = MessagingInAppImplementation.currentColorScheme
                self.threadUtil.runMain {
                    self.modalViewManager?.updateColorScheme(colorScheme)
                }
            }
            self.inAppMessageManager.subscribe(keyPath: \.colorScheme, subscriber: subscriber)
            return subscriber
        }()
    }

    open func unsubscribeFromInAppMessageState() {
        if let subscriber = inAppMessageStoreSubscriber {
            logger.logWithModuleTag("Unsubscribing BaseMessageManager from InAppMessageState", level: .debug)
            inAppMessageManager.unsubscribe(subscriber: subscriber)
            inAppMessageStoreSubscriber = nil
        }
        if let subscriber = colorSchemeSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
            colorSchemeSubscriber = nil
        }
    }

    private func finishDismissal(messageState: ModalMessageState) {
        removeEngineWebView()
        unsubscribeFromInAppMessageState()

        // If the message was explicitly dismissed (not just reset to initial)
        // then fetch next messages from queue
        if case .dismissed = messageState {
            gist.fetchUserMessagesFromRemoteQueue()
        }
    }

    /// Optional public method to kick off modal display timing or logs.
    /// (Used in some flows to explicitly measure "show time".)
    public func showMessage() {
        elapsedTimer.start(
            title: "Displaying modal for message: \(currentMessage.messageId)"
        )
    }
}

// MARK: - GistViewLifecycleDelegate

extension ModalMessageManager: GistViewLifecycleDelegate {
    /// For modal messages, we don't want to automatically dismiss when the view is removed from superview
    /// because the modal dismissal is handled by the ModalViewManager and state system
    public func gistViewWillRemoveFromSuperview(_ gistView: GistView) {
        logger.logWithModuleTag(
            "GistView being removed from superview for modal message: \(currentMessage.describeForLogs). No action taken.",
            level: .debug
        )
        // Intentionally not triggering dismissMessage() since modal dismissal is managed differently
    }
}
