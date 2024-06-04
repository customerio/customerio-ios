import CioInternalCommon
import Foundation
import UIKit

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
            checkIfMessageAvailableToDisplay()
        }
    }

    var runningHeightChangeAnimation: UIViewPropertyAnimator?

    // Get the height constraint for the View. Convenient to modify the height of the View.
    var viewHeightConstraint: NSLayoutConstraint? {
        constraints.first { $0.firstAnchor == heightAnchor }
    }

    private var inlineMessageManager: InlineMessageManager?

    public init(elementId: String) {
        super.init(frame: .zero)
        self.elementId = elementId

        // Setup the View and display a message, if one available. Since an elementId has been set.
        setupView()
        checkIfMessageAvailableToDisplay()
    }

    // This is called when the View is created from a Storyboard.
    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setupView()
        // An element id will not be set yet. No need to check for messages to display.
    }

    private func setupView() {
        // Customer did not set a height constraint. Create one so the View has one.
        // It's important to have only 1 active constraint for height or UIKit will ignore some constraints.
        // Try to re-use a constraint is one is already added instead of replacing it. Some scenarios such as
        // when UIView is nested in a UIStackView and distribution is .fillProportionally, the height constraint StackView adds is important to keep.
        if viewHeightConstraint == nil {
            heightAnchor.constraint(equalToConstant: 0).isActive = true
        }

        viewHeightConstraint?.priority = .required
        viewHeightConstraint?.constant = 0 // start at height 0 so the View does not show.
        getRootSuperview()?.layoutIfNeeded() // Since we modified constraint, perform a UI refresh to apply the change.

        // Begin listening to the queue for new messages.
        eventBus.addObserver(InAppMessagesFetchedEvent.self) { [weak self] _ in
            // EventBus callback function might not be on UI thread.
            // Switch to UI thread to update UI.
            Task { @MainActor in
                self?.checkIfMessageAvailableToDisplay()
            }
        }
    }

    private func checkIfMessageAvailableToDisplay() {
        guard let elementId = elementId else {
            return
        }

        let queueOfMessagesForGivenElementId = localMessageQueue.getInlineMessages(forElementId: elementId)
        let messageToDisplay = queueOfMessagesForGivenElementId.first

        if let messageToDisplay {
            displayInAppMessage(messageToDisplay)
        } else {
            dismissInAppMessage()
        }
    }

    private func displayInAppMessage(_ message: Message) {
        // Do not re-show the existing message if already shown to prevent the UI from flickering as it loads the same message again.
        if let currentlyShownMessage = inlineMessageManager?.currentMessage, currentlyShownMessage.messageId == message.messageId {
            return // already showing this message, exit early.
        }

        guard inlineMessageManager == nil else {
            // We are already displaying a messsage. In the future, we are planning on swapping the web content if there is another message in the local queue to display
            // and an inline message is dismissed. Until we add this feature, exit early.
            return
        }

        // Create a new manager for this new message to display and then display the manager's WebView.
        let newInlineMessageManager = InlineMessageManager(siteId: gist.siteId, message: message)
        newInlineMessageManager.inlineMessageDelegate = self

        guard let inlineView = newInlineMessageManager.inlineMessageView else {
            return // we dont expect this to happen, but better to handle it gracefully instead of force unwrapping
        }
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

    private func dismissInAppMessage() {
        // If this function gets called a lot in a short amount of time (eventbus triggers multiple events), the dismiss animation does not look as expected.
        // To fix this, exit early if dimiss has already been triggered.
        if inlineMessageManager?.inlineMessageDelegate == nil {
            return
        }

        inlineMessageManager?.inlineMessageDelegate = nil // remove the delegate to prevent any further callbacks from the WebView. If delegate events continue to come, this could cancel the dismiss animation and stop the dismiss action.

        animateHeight(to: 0)
    }

    private func animateHeight(to height: CGFloat) {
        // this function can be called multiple times in short period of time so we could be in the middle of 1 animation. Cancel the current one and start new.
        runningHeightChangeAnimation?.stopAnimation(true)

        runningHeightChangeAnimation = UIViewPropertyAnimator(duration: 0.3, curve: .easeIn, animations: {
            self.viewHeightConstraint?.constant = height // Changing the height in animation block indicates we want to animate the height change.

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
}

extension InAppMessageView: InlineMessageManagerDelegate {
    // This function is called by WebView when the content's size changes.
    public func sizeChanged(width: CGFloat, height: CGFloat) {
        Task { @MainActor in // only update UI on main thread. This delegate function may not get called from UI thread.
            // We keep the width the same to what the customer set it as.
            // Update the height to match the aspect ratio of the web content.
            self.animateHeight(to: height)
        }
    }
}
