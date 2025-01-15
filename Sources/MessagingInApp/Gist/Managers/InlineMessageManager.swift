import Foundation

protocol InlineMessageManagerDelegate: AnyObject {
    func sizeChanged(width: CGFloat, height: CGFloat)
    func onCloseAction()
    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) -> Bool
    func willChangeMessage(newTemplateId: String)
}

class InlineMessageManager: BaseMessageManager {
    // MARK: - Properties

    weak var inlineDelegate: InlineMessageManagerDelegate?

    // Ensure GistView has delegate set
    var inlineMessageView: GistView {
        if gistView.delegate == nil {
            gistView.delegate = self
        }
        return gistView
    }

    // MARK: - Lifecycle

    override func cleanup() {
        inlineDelegate = nil
        super.cleanup()
    }

    // MARK: - Message Handling

    override func handleMessageLoaded() {
        super.handleMessageLoaded()
        // The Inline View is responsible for making the in-app message visible in the UI
        inAppMessageManager.dispatch(action: .displayMessage(message: currentMessage))
    }

    // MARK: - Action Handling

    override func onDeepLinkOpened() {
        // Do not do anything. Continue showing the in-app message.
    }

    override func handleRouteChange(_ route: String) {
        super.handleRouteChange(route)
        inlineDelegate?.willChangeMessage(newTemplateId: route)
    }

    func onCloseAction() {
        super.dismissMessage()
        inlineDelegate?.onCloseAction()
    }

    override func onReplaceMessage(newMessageToShow: Message) {
        // Not yet implemented. Planned in future update.
    }

    override func onTapAction(message: Message, currentRoute: String, action: String, name: String) {
        // Let inline delegate handle the action first
        let didInlineViewHandleAction = inlineDelegate?.onInlineButtonAction(
            message: message,
            currentRoute: currentRoute,
            action: action,
            name: name
        ) ?? false

        // Only forward to main delegate if inline didn't handle it
        if !didInlineViewHandleAction {
            delegate?.action(message: message, currentRoute: currentRoute, action: action, name: name)
        }
    }
}

// MARK: - GistViewDelegate

extension InlineMessageManager: GistViewDelegate {
    func sizeChanged(message: Message, width: CGFloat, height: CGFloat) {
        inlineDelegate?.sizeChanged(width: width, height: height)
    }

    func action(message: Message, currentRoute: String, action: String, name: String) {
        // Handling event in the manager onTapAction() function.
    }
}
