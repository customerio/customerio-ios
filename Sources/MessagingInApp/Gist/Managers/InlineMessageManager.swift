import Foundation

// Callbacks specific to inline message events.
protocol InlineMessageManagerDelegate: AnyObject {
    func sizeChanged(width: CGFloat, height: CGFloat)
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
    var inlineMessageView: GistView? {
        let view = super.gistView
        view?.delegate = self
        return view
    }

    weak var inlineMessageDelegate: InlineMessageManagerDelegate?

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

    override func onCloseAction() {
        // Not yet implemented. Planned in future update.
    }
}

extension InlineMessageManager: GistViewDelegate {
    func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        inlineMessageDelegate?.sizeChanged(width: width, height: height)
    }

    func action(message: Message, currentRoute: String, action: String, name: String) {
        // Action button handling is processed by the superclass. Ignore this callback and instead use one of the superclass event callback functions.
    }
}
