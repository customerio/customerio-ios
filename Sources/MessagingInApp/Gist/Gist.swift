import CioInternalCommon
import Foundation
import UIKit

protocol GistInstance: AutoMockable {
    var siteId: String { get }
    func showMessage(_ message: Message, position: MessagePosition) -> Bool
}

public class Gist: GistInstance, GistDelegate {
    var shownModalMessageQueueIds: Set<String> = [] // all modal messages that have been shown in the app already.
    var messageQueueManager: MessageQueueManager {
        DIGraphShared.shared.messageQueueManager
    }

    private var messageManagers: [ModalMessageManager] = []
    public var siteId: String = ""
    public var dataCenter: String = ""

    public weak var delegate: GistDelegate?

    public static let shared = Gist()

    public func setup(
        siteId: String,
        dataCenter: String,
        logging: Bool = false,
        env: GistEnvironment = .production
    ) {
        Settings.Environment = env
        self.siteId = siteId
        self.dataCenter = dataCenter
        Logger.instance.enabled = logging
        messageQueueManager.setup(skipQueueCheck: false)

        // To finish initializing of Gist, we want to fetch fonts and other assets for HTML in-app messages.
        // To do that, we try to display a message with an empty message id.
        _ = InlineMessageManager(siteId: self.siteId, message: Message(templateId: ""))
    }

    // For testing to reset the singleton state
    func reset() {
        clearUserToken()
        messageManagers = []
        RouteManager.clearCurrentRoute()
    }

    // MARK: User

    public func setUserToken(_ userToken: String) {
        UserManager().setUserToken(userToken: userToken)
    }

    public func clearUserToken() {
        cancelModalMessage(ifDoesNotMatchRoute: "") // provide a new route to trigger a modal cancel.
        messageQueueManager.clearLocalStore()
        UserManager().clearUserToken()
        messageQueueManager.clearUserMessagesFromLocalStore()
    }

    // MARK: Route

    public func getCurrentRoute() -> String {
        RouteManager.getCurrentRoute()
    }

    public func setCurrentRoute(_ currentRoute: String) {
        if RouteManager.getCurrentRoute() == currentRoute {
            return // ignore request, route has not changed.
        }

        cancelModalMessage(ifDoesNotMatchRoute: currentRoute)

        RouteManager.setCurrentRoute(currentRoute)
        messageQueueManager.fetchUserMessagesFromLocalStore()
    }

    public func clearCurrentRoute() {
        RouteManager.clearCurrentRoute()
    }

    // MARK: Message Actions

    public func showMessage(_ message: Message, position: MessagePosition) -> Bool {
        if let messageManager = getModalMessageManager() {
            Logger.instance.info(message: "Message cannot be displayed, \(messageManager.currentMessage.templateId) is being displayed.")
        } else {
            let messageManager = createMessageManager(siteId: siteId, message: message)
            messageManager.showMessage(position: position)
            return true
        }
        return false
    }

    public func showMessage(_ message: Message) -> Bool {
        showMessage(message, position: .center)
    }

    public func dismissMessage(instanceId: String? = nil, completionHandler: (() -> Void)? = nil) {
        if let id = instanceId, let messageManager = messageManager(instanceId: id) {
            messageManager.removePersistentMessage()
            messageManager.dismissMessage(completionHandler: completionHandler)
        } else {
            getModalMessageManager()?.dismissMessage(completionHandler: completionHandler)
        }
    }

    // MARK: Events

    public func messageShown(message: Message) {
        Logger.instance.debug(message: "Message with route: \(message.templateId) shown")
        if message.gistProperties.persistent != true {
            logMessageView(message: message)
        } else {
            Logger.instance.debug(message: "Persistent message shown, skipping logging view")
        }
        delegate?.messageShown(message: message)
    }

    public func messageDismissed(message: Message) {
        Logger.instance.debug(message: "Message with id: \(message.templateId) dismissed")
        removeMessageManager(instanceId: message.instanceId)
        delegate?.messageDismissed(message: message)

        messageQueueManager.fetchUserMessagesFromLocalStore()
    }

    public func messageError(message: Message) {
        removeMessageManager(instanceId: message.instanceId)
        delegate?.messageError(message: message)
    }

    public func action(message: Message, currentRoute: String, action: String, name: String, shouldTrackMetric: Bool = true) {
        delegate?.action(message: message, currentRoute: currentRoute, action: action, name: name, shouldTrackMetric: shouldTrackMetric)
    }

    func logMessageView(message: Message) {
        // This function body reports metrics and makes sure that messages are not shown 2+ times.
        messageQueueManager.removeMessageFromLocalStore(message: message)
        if let id = message.id {
            shownModalMessageQueueIds.insert(id)
        }
        let userToken = UserManager().getUserToken()
        LogManager(siteId: siteId, dataCenter: dataCenter)
            .logView(message: message, userToken: userToken) { response in
                if case .failure(let error) = response {
                    Logger.instance.error(message: "Failed to log view for message: \(message.templateId) with error: \(error)")
                }
            }
    }

    // When the user navigates to a different screen, modal messages should only appear if they are meant for the current screen.
    // If the currently displayed/loading modal message has a page rule, it should not be shown anymore.
    private func cancelModalMessage(ifDoesNotMatchRoute newRoute: String) {
        if let messageManager = getModalMessageManager() {
            let modalMessageLoadingOrDisplayed = messageManager.currentMessage

            if modalMessageLoadingOrDisplayed.doesHavePageRule(), !modalMessageLoadingOrDisplayed.doesPageRuleMatch(route: newRoute) {
                // the page rule has changed and the currently loading/visible modal has page rules set, it should no longer be shown.
                Logger.instance.debug(message: "Cancelled showing message with id: \(modalMessageLoadingOrDisplayed.templateId)")

                // Stop showing the current message synchronously meaning to remove from UI instantly.
                // We want to be sure the message is gone when this function returns and be ready to display another message if needed.
                messageManager.cancelShowingMessage()

                // Removing the message manager allows you to show a new modal message. Otherwise, request to show will be ignored.
                removeMessageManager(instanceId: modalMessageLoadingOrDisplayed.instanceId)
            }
        }
    }

    // Message Manager

    private func createMessageManager(siteId: String, message: Message) -> ModalMessageManager {
        let messageManager = ModalMessageManager(siteId: siteId, message: message)
        messageManager.delegate = self
        messageManagers.append(messageManager)
        return messageManager
    }

    func getModalMessageManager() -> ModalMessageManager? {
        messageManagers.first
    }

    func messageManager(instanceId: String) -> ModalMessageManager? {
        messageManagers.first(where: { $0.currentMessage.instanceId == instanceId })
    }

    func removeMessageManager(instanceId: String) {
        messageManagers.removeAll(where: { $0.currentMessage.instanceId == instanceId })
    }
}

// Convenient way for other modules to access instance as well as being able to mock instance in tests.
extension DIGraphShared {
    var gist: GistInstance {
        if let override: GistInstance = getOverriddenInstance() {
            return override
        }

        return Gist.shared
    }
}
