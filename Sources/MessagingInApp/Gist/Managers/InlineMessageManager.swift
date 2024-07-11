import Foundation

// Callbacks specific to inline message events.
protocol InlineMessageManagerDelegate: AnyObject {
    func sizeChanged(width: CGFloat, height: CGFloat)
    func onCloseAction()
    func willChangeMessage(newTemplateId: String)
    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String)
}

/**
 Class that implements the business logic for a inline message being displayed. Handle when action buttons are clicked, render the HTML message, and get callbacks for inline message events.

 Usage:
 ```
 let inlineMessageManager = InlineMessageManager(siteId: "", message: message)
 inlineMessageManager.inlineMessageDelegate = self // Get callbacks for inline message events.
 inlineMessageManager.inlineMessageView // View that displays the in-app web message
 ```
 */
class InlineMessageManager: MessageManager {
    var inlineMessageView: GistView {
        if super.gistView.delegate == nil {
            super.gistView.delegate = self
        }

        return super.gistView
    }

    weak var inlineMessageDelegate: InlineMessageManagerDelegate?

    override func stopAndCleanup() {
        inlineMessageDelegate = nil

        super.stopAndCleanup()
    }

    override func onReplaceMessage(newMessageToShow: Message) {
        // Not yet implemented. Planned in future update.
    }

    override func onDoneLoadingMessage(routeLoaded: String, onComplete: @escaping () -> Void) {
        // The Inline View is responsible for making the in-app message visible in the UI. No logic needed in the manager.
        onComplete()
    }

    override func onDeepLinkOpened() {
        // Do not do anything. Continue showing the in-app message.
    }

    override func willChangeMessage(newTemplateId: String) {
        inlineMessageDelegate?.willChangeMessage(newTemplateId: newTemplateId)
    }

    override func onCloseAction() {
        inlineMessageDelegate?.onCloseAction()
    }

    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) {
        inlineMessageDelegate?.onInlineButtonAction(message: message, currentRoute: currentRoute, action: action, name: name)
    }
}

extension InlineMessageManager: GistViewDelegate {
    func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        inlineMessageDelegate?.sizeChanged(width: width, height: height)
    }

    func action(message: Message, currentRoute: String, action: String, name: String) {
        inlineMessageDelegate?.onInlineButtonAction(message: message, currentRoute: currentRoute, action: action, name: name)
    }
}
