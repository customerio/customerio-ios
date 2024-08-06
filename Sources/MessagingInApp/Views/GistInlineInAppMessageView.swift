import CioInternalCommon
import Foundation
import UIKit

// Event listener for interactions and state changes to an inline inapp message that's rendered.
public protocol GistInlineInAppMessageViewDelegate: AnyObject {
    // After a message is finished rendering and the size may have changed.
    func onMessageRendered(width: CGFloat, height: CGFloat)
    // If there is no longer any messages to be shown.
    func onNoMessageToDisplay()
    // A custom action button is pressed.
    // @return if you handled the action yourself.
    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) -> Bool
    // If the inline View is going to show a different message. Example: When a user clicks "show another message" action buttons.
    func willChangeMessage(newTemplateId: String, onComplete: @escaping () -> Void)
}

/**
 UIView that can render and display an web in-app message.

 Responsibilities:
 * Given an elementId, it will get a message to display for that elemenetId.
 * Dynamically change the height and width of the UIView to match aspect ratio of the in-app message
 * Communicate events to a delegate. This allows you to customize the look of an inline message in your app!

 This UIView is designed to not be opinionated on how an inline in-app message is displayed in an app. Anyone (including customers) can create a wrapper around this UIView in their UIKit or SwiftUI app and modify how in-app messages are shown.
 */
public class GistInlineInAppMessageView: UIView {
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

    private var contentSize: CGSize = .zero {
        didSet {
            // Notify the system that the intrinsic content size has changed
            invalidateIntrinsicContentSize()
        }
    }

    // How the View communicates the size of the in-app message that's rendered.
    // UIKit and SwiftUI frameworks use the intrinsicContentSize to adjust auto layout constraints automaticaly to display the View correctly.
    // Note: If you want to animate when the content size changes, create a wrapper around this View and listen to delegate events. The intrinsicContentSize instantly changes the size.
    override public var intrinsicContentSize: CGSize {
        contentSize
    }

    func updateContentSize(newHeight: CGFloat, newWidth: CGFloat) {
        contentSize = .init(width: newWidth, height: newHeight)
    }

    public weak var delegate: GistInlineInAppMessageViewDelegate?

    // When a fetch request is performed, it's an async operation to have the inline View notified about this fetch and the inline View processing the fetch.
    // There is currently no easy way to know when the inline View has finished processing the fetch.
    // This listener is a hack for our automated tests to know when the inline View has finished processing the fetch.
    //
    // See linear ticket MBL-427 to learn more about this limitation in our tests.
    var refreshViewListener: (() -> Void)?

    // Inline messages that have already been shown by this View instance.
    // This is used to prevent showing the same message multiple times when the close button is pressed.
    var previouslyShownMessages: [Message] = []

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
        defer {
            // Always call the refreshViewListener at the end of the function to know processing is done.
            refreshViewListener?()
        }

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
            delegate?.onNoMessageToDisplay()
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
            delegate?.willChangeMessage(newTemplateId: message.templateId) {
                // After the delegate is done, cleanup resources since we no longer need to show the previous message.
                self.stopShowingMessageAndCleanup()
                self.beginShowing(message: message)
            }
        } else {
            beginShowing(message: message)
        }
    }

    // Call when you want to begin the process of showing a new message.
    private func beginShowing(message: Message) {
        // Create a new manager for this new message to display and then display the manager's WebView.
        let newInlineMessageManager = InlineMessageManager(siteId: gist.siteId, message: message)
        newInlineMessageManager.inlineMessageDelegate = self
        // Gist class is what Modal messages use as the modal message manager delegate.
        // So we can re-use modal message logic, set the Gist class for inline managers, too.
        newInlineMessageManager.delegate = Gist.shared

        let inlineView = newInlineMessageManager.inlineMessageView

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
}

extension GistInlineInAppMessageView: InlineMessageManagerDelegate {
    // This function is called by WebView when the content's size changes.
    public func sizeChanged(width: CGFloat, height: CGFloat) {
        Task { @MainActor in // only update UI on main thread. This delegate function may not get called from UI thread.
            // We keep the width the same to what the customer set it as.
            // Update the height to match the aspect ratio of the web content.

            self.updateContentSize(newHeight: height, newWidth: width)
            self.delegate?.onMessageRendered(width: width, height: height)
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
            self.delegate?.willChangeMessage(newTemplateId: newTemplateId, onComplete: {
                // Nothing to do when the animation is complete.
                // the sizeChanged function will be called when the next message is rendered. sizeChanged will animate in the message for us.
            })
        }
    }

    // This method is called by InlineMessageManager when custom action button is tapped
    // on an inline in-app message.
    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) -> Bool {
        guard let delegate = delegate else {
            return false
        }

        return delegate.onInlineButtonAction(message: message, currentRoute: currentRoute, action: action, name: name)
    }
}
