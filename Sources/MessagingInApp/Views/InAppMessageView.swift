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

    // Can set in the constructor or can set later (like if you use Storyboards)
    public var elementId: String? {
        didSet {
            checkIfMessageAvailableToDisplay()
        }
    }

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
        // next, configure the View such as setting the position and size. This will come in a future change.
    }

    private func checkIfMessageAvailableToDisplay() {
        // In a future PR, we will remove the asyncAfter(). this is only for testing in sample apps because when app opens, the local queue is empty. so wait to check messages until first fetch is done.
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
        guard let elementId = elementId else {
            return
        }

        let queueOfMessagesForGivenElementId = localMessageQueue.getInlineMessages(forElementId: elementId)
        guard let messageToDisplay = queueOfMessagesForGivenElementId.first else {
            return // no messages to display, exit early. In the future we will dismiss the View.
        }

        // next, display the message
    }
}
