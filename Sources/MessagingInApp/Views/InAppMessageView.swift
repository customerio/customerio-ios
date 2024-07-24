import CioInternalCommon
import Foundation
import UIKit

// To handle inline custom button actions.
public protocol InAppMessageViewActionDelegate: AnyObject, AutoMockable {
    // This method is called when a custom button is tapped in an inline message.
    func onActionClick(message: InAppMessage, actionValue: String, actionName: String)
}

/**
 View that can be added to a customer's app UI to display inline in-app messages.

 Usage:
 1. Create an instance of this View and add it to the customer's app UI.
 ```
 // you can construct an instance with code:
 let inAppMessageView = InAppMessageView(elementId: "elementId")
 view.addSubView(inAppMessageView)

 // Or, if you use Storyboards:
 @IBOutlet weak var inAppMessageView: InAppMessageView!
 inAppMessageView.elementId = "elementId"
 ```
 2. Position and set size of the View in app's UI. The View will adjust it's height automatically, but all other constraints are the responsibilty of app developer. You can set a height constraint if you want autolayout warnings to go away but know that the View will ignore this set height.
 */
public class InAppMessageView: UIView {
    private var localMessageQueue: MessageQueueManager {
        DIGraphShared.shared.messageQueueManager
    }

    private var gist: GistInstance {
        DIGraphShared.shared.gist
    }

    private var eventBus: EventBusHandler {
        DIGraphShared.shared.eventBusHandler
    }

    // Can set in the constructor or can set later (like if you use Storyboards)
    public var elementId: String? {
        didSet {
            refreshView()
        }
    }

    // Delegate to handle custom action button tap.
    public weak var onActionDelegate: InAppMessageViewActionDelegate?

    // Inline messages that have already been shown by this View instance.
    // This is used to prevent showing the same message multiple times when the close button is pressed.
    //
    // When persistent vs non-persistent messages and metrics features are implemented in the SDK, this array may be
    // replaced with a global list of shown messages.
    var previouslyShownMessages: [Message] = []

    var runningHeightChangeAnimation: UIViewPropertyAnimator?
    var runningCrossFadeAnimation: UIViewPropertyAnimator?

    var messageRenderingLoadingView: UIView? {
        subviews.first { $0 is UIActivityIndicatorView }
    }

    var inAppMessageView: UIView? {
        subviews.first { $0 == inlineMessageManager?.inlineMessageView }
    }

    var inlineMessageManager: InlineMessageManager?

    // Determines if the View is already trying to show a message or not.
    private var isRenderingOrDisplayingAMessage: Bool {
        inlineMessageManager != nil
    }

    public init(elementId: String) {
        super.init(frame: .zero)
        self.elementId = elementId

        // Setup the View and display a message, if one available. Since an elementId has been set.
        setupView()
        refreshView()
    }

    // This is called when the View is created from a Storyboard.
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setupView()
        // An element id will not be set yet. No need to check for messages to display.
    }

    private func setupView() {
        // It's important to have only 1 active constraint for height or UIKit will ignore some constraints.
        // Try to re-use a constraint if one is already added instead of replacing it. Some scenarios such as
        // when UIView is nested in a UIStackView and distribution is .fillProportionally, the height constraint StackView adds is important to keep.

        if heightConstraint == nil {
            // Customer did not set a height constraint. Create one so the View has one.
            let heightConstraint = heightAnchor.constraint(equalToConstant: 0)
            heightConstraint.priority = .required // in case a customer sets a height constraint, by us setting the highest priority, we try to have this constraint be used.
            heightConstraint.isActive = true // set isActive as the last step.
        }

        heightConstraint?.constant = 0 // start at height 0 so the View does not show.
        getRootSuperview()?.layoutIfNeeded() // Since we modified constraint, perform a UI refresh to apply the change.

        // Begin listening to the queue for new messages.
        eventBus.addObserver(InAppMessagesFetchedEvent.self) { [weak self] _ in
            // EventBus callback function might not be on UI thread.
            // Switch to UI thread to update UI.
            Task { @MainActor in
                self?.refreshView()
            }
        }
    }

    // Updates the state of the View, if needed. Call as often as you need if an event happens that may cause the View to need to update.
    private func refreshView(forceShowNextMessage: Bool = false) {
        guard let elementId = elementId else {
            return // we cannot check if a message is available until element id set on View.
        }

        let queueOfMessagesForGivenElementId = localMessageQueue.getInlineMessages(forElementId: elementId)
        let messageAvailableToDisplay = queueOfMessagesForGivenElementId.first { !hasBeenPreviouslyShown($0) }

        if !forceShowNextMessage, isRenderingOrDisplayingAMessage {
            // We are already displaying or rendering a messsage. Do not show another message until the current message is closed.
            // The main reason for this is when a message is tracked as "opened", the Gist backend will not return this message on the next fetch call.
            // We want to coninue showing a message even if the fetch no longer returns the message and the message is currently visible.
            return
        }

        if let messageAvailableToDisplay {
            displayInAppMessage(messageAvailableToDisplay)
        } else {
            dismissInAppMessage()
        }
    }

    // Function to check if a message has been previously shown
    func hasBeenPreviouslyShown(_ message: Message) -> Bool {
        previouslyShownMessages.contains { $0.id == message.id }
    }

    private func displayInAppMessage(_ message: Message) {
        // If this function gets called a lot in a short amount of time (eventbus triggers multiple events), the display animation does not look as expected.
        // To fix this, exit early if display has already been triggered.
        if let currentlyShownMessage = inlineMessageManager?.currentMessage, currentlyShownMessage.id == message.id {
            return // already showing this message or in the process of showing it.
        }

        // If a different message is currently being shown, we want to replace the currently shown message with new message.
        if isRenderingOrDisplayingAMessage {
            showLoadingView {
                // After animation is over, cleanup resources since we no longer need to show the previous message.
                self.stopShowingMessageAndCleanup()
                self.beginShowing(message: message)
            }
        } else {
            beginShowing(message: message)
        }
    }

    // Call when you want to show the loading View, indicating to the app user that a new message is being loaded.
    private func showLoadingView(onComplete: @escaping () -> Void) {
        // Before we begin showing loading view, check to see if we are in the correct state that we should perform this change.
        // This is a safety check in case this function gets called multiple times. We don't want the UI to flicker by changing multiple times.
        guard let currentlyDisplayedInAppWebView = inAppMessageView, messageRenderingLoadingView == nil else {
            return onComplete()
        }

        // To provide the user with feedback indicating a new message is being rendered, show an activity indicator while the new message is loading.
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.startAnimating()
        activityIndicator.isHidden = true // start hidden so when we add the subview, it does not cause a flicker in the UI. Wait to show it when the animation begins.

        addSubview(activityIndicator)
        assert(messageRenderingLoadingView != nil, "Expect activity indicator to be added as a subview")

        // Set autolayout constraints to position the activity indicator.
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            activityIndicator.widthAnchor.constraint(equalTo: widthAnchor),
            activityIndicator.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        animateFadeInOutInlineView(fromView: currentlyDisplayedInAppWebView, toView: activityIndicator) {
            onComplete()
        }
    }

    // Call when you want to begin the process of showing a new message.
    private func beginShowing(message: Message) {
        // Create a new manager for this new message to display and then display the manager's WebView.
        let newInlineMessageManager = InlineMessageManager(siteId: gist.siteId, message: message)
        newInlineMessageManager.inlineMessageDelegate = self

        let inlineView = newInlineMessageManager.inlineMessageView
        inlineView.isHidden = true // start hidden while the message renders. When complete, it will show the View.

        addSubview(inlineView)

        // Setup the WebView to be the same size as this View. When this View changes size, the WebView will change, too.
        inlineView.translatesAutoresizingMaskIntoConstraints = false // Required in order for this inline View to have full control over the AutoLayout constraints for the WebView.
        NSLayoutConstraint.activate([
            inlineView.topAnchor.constraint(equalTo: topAnchor),
            inlineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inlineView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inlineView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        inlineMessageManager = newInlineMessageManager
    }

    private func stopShowingMessageAndCleanup() {
        // If a message is currently being shown, cleanup and remove the webview so we can begin showing a new message.
        // Cleanup needs to involve removing the WebView from it's superview and cleaning up the WebView's resources.
        inlineMessageManager?.stopAndCleanup()
        inlineMessageManager?.inlineMessageView.removeFromSuperview()
        inlineMessageManager = nil
    }

    private func dismissInAppMessage() {
        // If this function gets called a lot in a short amount of time (eventbus triggers multiple events), the dismiss animation does not look as expected.
        // To fix this, exit early if dismiss has already been triggered.
        if inlineMessageManager?.inlineMessageDelegate == nil {
            return
        }

        stopShowingMessageAndCleanup()

        animateHeight(to: 0)
    }

    private func animateHeight(to height: CGFloat) {
        // this function can be called multiple times in short period of time so we could be in the middle of 1 animation. Cancel the current one and start new.
        runningHeightChangeAnimation?.stopAnimation(true)

        runningHeightChangeAnimation = UIViewPropertyAnimator(duration: 0.3, curve: .easeIn, animations: {
            self.heightConstraint?.constant = height // Changing the height in animation block indicates we want to animate the height change.

            // Since we modified constraint, perform a UI refresh to apply the change.
            // It's important that we call layoutIfNeeded on the topmost superview in the hierarchy. During development, there were animiation issues if layoutIfNeeded was called on a different superview then the root.
            // Example, given this UI:
            // UIViewController
            // └── UIStackView
            //    └── InAppMessageView
            // ...If we call layoutIfNeeded on superview (UIStackView), the animation will not work as expected.
            // This is also why it's important that we do QA testing on the inline View when it's nested in a UIStackView.
            self.getRootSuperview()?.layoutIfNeeded()
        })

        runningHeightChangeAnimation?.startAnimation()
    }

    // Takes in 2 Views. In 1 single animation, fades in 1 View while fading out the other.
    private func animateFadeInOutInlineView(fromView: UIView, toView: UIView, onComplete: (() -> Void)?) {
        runningCrossFadeAnimation?.stopAnimation(true) // cancel previous fade animation if there is one to assert this one will be called.

        // Set an initial state for `toView` to begin the animation. Make sure the View is not hidden and is fully opaque.
        toView.isHidden = false
        toView.alpha = 0

        // These are the final values that we are looking for after the animation.
        runningCrossFadeAnimation = UIViewPropertyAnimator(duration: 0.1, curve: .linear, animations: {
            fromView.alpha = 0
            toView.alpha = 1
        })

        runningCrossFadeAnimation?.addCompletion { _ in
            fromView.isHidden = true
            onComplete?()
        }

        runningCrossFadeAnimation?.startAnimation()
    }
}

extension InAppMessageView: InlineMessageManagerDelegate {
    // This function is called by WebView when the content's size changes.
    public func sizeChanged(width: CGFloat, height: CGFloat) {
        Task { @MainActor in // only update UI on main thread. This delegate function may not get called from UI thread.
            // We keep the width the same to what the customer set it as.
            // Update the height to match the aspect ratio of the web content.

            guard let inAppMessageView = self.inAppMessageView else {
                return
            }

            inAppMessageView.isHidden = false
            self.animateHeight(to: height)

            if let messageRenderingLoadingView = self.messageRenderingLoadingView {
                animateFadeInOutInlineView(fromView: messageRenderingLoadingView, toView: inAppMessageView) {
                    messageRenderingLoadingView.removeFromSuperview()
                }
            }
        }
    }

    func onCloseAction() {
        Task { @MainActor in
            if let currentlyShownMessage = inlineMessageManager?.currentMessage {
                previouslyShownMessages.append(currentlyShownMessage)
            }

            self.refreshView(forceShowNextMessage: true)
        }
    }

    // Called when "show another message" action button is clicked.
    func willChangeMessage(newTemplateId: String) {
        Task { @MainActor in
            // Animate in a loading view while the next message is being rendered.
            self.showLoadingView {
                // Nothing to do when the animation is complete.
                // the sizeChanged function will be called when the next message is rendered. sizeChanged will animate in the message for us.
            }
        }
    }

    // This method is called by InlineMessageManager when custom action button is tapped
    // on an inline in-app message.
    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) {
        // If delegate is not set then call the global `messageActionTaken` method
        guard let onActionDelegate = onActionDelegate else {
            Gist.shared.action(message: message, currentRoute: currentRoute, action: action, name: name)
            return
        }
        onActionDelegate.onActionClick(message: InAppMessage(gistMessage: message), actionValue: action, actionName: name)
    }
}

// SwiftUI
#if canImport(SwiftUI)
import SwiftUI
@available(iOS 13.0, *)
public struct InAppMessageViewRepresentable: UIViewRepresentable {
    public var elementId: String
    public var onActionClick: ((InAppMessage, String, String) -> Void)?

    public init(elementId: String, onActionClick: ((InAppMessage, String, String) -> Void)? = nil) {
        self.elementId = elementId
        self.onActionClick = onActionClick
    }

    public func makeUIView(context: Context) -> InAppMessageView {
        let inlineMessageView = InAppMessageView(elementId: elementId)
        // This is optional. If set, the delegate method `onActionClick`
        // will receive callbacks.
        // If not set, the global method `messageActionTaken` will handle the callbacks.
        if let _ = onActionClick {
            inlineMessageView.onActionDelegate = context.coordinator
        }
        return inlineMessageView
    }

    public func updateUIView(_ uiView: InAppMessageView, context: Context) {
        // Update your view here if needed
    }

//     Coordinator to handle delegate `InAppMessageViewActionDelegate`
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, InAppMessageViewActionDelegate {
        var parent: InAppMessageViewRepresentable

        init(_ parent: InAppMessageViewRepresentable) {
            self.parent = parent
        }

        // Delegate method for handling custom button action clicks
        public func onActionClick(message: InAppMessage, actionValue: String, actionName: String) {
            parent.onActionClick?(message, actionValue, actionName)
        }
    }
}
#endif
