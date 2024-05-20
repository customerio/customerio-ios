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

    // Can set in the constructor or can set later (like if you use Storyboards)
    public var elementId: String? {
        didSet {
            checkIfMessageAvailableToDisplay()
        }
    }

    var heightConstraint: NSLayoutConstraint!

    // Get the View's current height or change the height by setting a new value.
    private var viewHeight: CGFloat {
        get {
            heightConstraint.constant
        }
        set {
            heightConstraint.constant = newValue
            layoutIfNeeded()
        }
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
        // Remove any existing height constraints added by customer.
        // This is required as only 1 height constraint can be active at a time. Our height constraint will be ignored
        // if we do not do this.
        for existingViewConstraint in constraints where existingViewConstraint.firstAnchor == heightAnchor {
            existingViewConstraint.isActive = false
        }

        // Create a view constraint for the height of the View.
        // This allows us to dynamically update the height at a later time.
        //
        // Set the initial height of the view to 0 so it's not visible.
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
        layoutIfNeeded()
    }

    private func checkIfMessageAvailableToDisplay() {
        guard let elementId = elementId else {
            return
        }

        let queueOfMessagesForGivenElementId = localMessageQueue.getInlineMessages(forElementId: elementId)
        guard let messageToDisplay = queueOfMessagesForGivenElementId.first else {
            return // no messages to display, exit early. In the future we will dismiss the View.
        }

        displayInAppMessage(messageToDisplay)
    }

    private func displayInAppMessage(_ message: Message) {
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
}

extension InAppMessageView: InlineMessageManagerDelegate {
    // This function is called by WebView when the content's size changes.
    public func sizeChanged(width: CGFloat, height: CGFloat) {
        // We keep the width the same to what the customer set it as.
        // Update the height to match the aspect ratio of the web content.
        viewHeight = height
    }
}
