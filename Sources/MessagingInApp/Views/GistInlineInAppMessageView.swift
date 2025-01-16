import CioInternalCommon
import Foundation
import UIKit

// Event listener for interactions and state changes to an inline inapp message that's rendered.
public protocol GistInlineMessageUIViewDelegate: AnyObject {
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

// TODO: Reimplement this class from feature branch.
public class GistInlineMessageUIView: UIView {
    public var elementId: String?
    public weak var delegate: GistInlineMessageUIViewDelegate?

    public init(elementId: String) {
        super.init(frame: .zero)
        self.elementId = elementId
    }

    // This is called when the View is created from a Storyboard.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
