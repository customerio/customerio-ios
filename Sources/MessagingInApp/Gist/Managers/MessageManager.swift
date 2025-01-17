import CioInternalCommon
import Foundation
import UIKit

/// Abstract base class that contains shared logic for both Modal and Inline message managers.
public class BaseMessageManager: EngineWebDelegate {
    // MARK: - Dependencies

    public let logger: Logger
    let inAppMessageManager: InAppMessageManager
    public let threadUtil: ThreadUtil
    let gist: GistProvider
    let engineWebProvider: EngineWebProvider

    // MARK: - Message & State

    public let currentMessage: Message
    public var currentRoute: String
    public let isMessageEmbed: Bool

    @Atomic public var isMessageLoaded: Bool = false
    var inAppMessageStoreSubscriber: InAppMessageStoreSubscriber?
    var elapsedTimer = ElapsedTimer()
    var engine: EngineWebInstance!
    var gistView: GistView!

    // MARK: - Init & Deinit

    init(state: InAppMessageState, message: Message) {
        self.currentMessage = message
        self.currentRoute = message.messageId
        self.isMessageEmbed = !(message.gistProperties.elementId?.isBlankOrEmpty() ?? true)

        let diGraph = DIGraphShared.shared
        self.logger = diGraph.logger
        self.inAppMessageManager = diGraph.inAppMessageManager
        self.threadUtil = diGraph.threadUtil
        self.gist = diGraph.gistProvider
        self.engineWebProvider = diGraph.engineWebProvider

        // Setup engine configuration
        let engineWebConfiguration = EngineWebConfiguration(
            siteId: state.siteId,
            dataCenter: state.dataCenter,
            instanceId: message.instanceId,
            endpoint: state.environment.networkSettings.engineAPI,
            messageId: message.messageId,
            properties: message.properties.mapValues { AnyEncodable($0) }
        )

        // Create the engine
        self.engine = engineWebProvider.getEngineWebInstance(
            configuration: engineWebConfiguration,
            state: state,
            message: message
        )
        engine.delegate = self

        // Create the GistView container
        self.gistView = GistView(message: currentMessage, engineView: engine.view)

        // Subscribe to state changes
        subscribeToInAppMessageState()
    }

    deinit {
        unsubscribeFromInAppMessageState()
        removeEngineWebView()
    }

    // MARK: - Subscription to InAppMessageState

    func subscribeToInAppMessageState() {
        // Keep a strong reference to the subscriber to prevent deallocation and continue receiving updates
        // Also, since we do not store strong reference of MessageManager anywhere, not keeping a strong reference of
        // subscriber may result in deallocation of MessageManager and hence dismissal of message unexpectedly.
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [self] state in
                let messageState = state.currentMessageState
                switch messageState {
                case .displayed:
                    threadUtil.runMain {
                        // Subclasses (Modal or Inline) can show differently
                        self.onMessageDisplayed()
                    }

                // Dismiss the message when the message is dismissed or initial state
                // Initial state may only be received when state is reset while a message was being displayed
                case .dismissed, .initial:
                    threadUtil.runMain {
                        // Dismiss the message from subclass
                        self.onMessageDismissed(messageState: messageState)
                    }

                default:
                    break
                }
            }
            inAppMessageManager.subscribe(keyPath: \.currentMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    open func unsubscribeFromInAppMessageState() {
        guard let subscriber = inAppMessageStoreSubscriber else { return }

        logger.logWithModuleTag("Unsubscribing BaseMessageManager from InAppMessageState", level: .debug)
        inAppMessageManager.unsubscribe(subscriber: subscriber)
        inAppMessageStoreSubscriber = nil
    }

    // MARK: - Engine Cleanup

    open func removeEngineWebView() {
        guard engine.delegate != nil else { return }
        logger.logWithModuleTag("Cleaning EngineWebView from BaseMessageManager", level: .debug)
        engine.cleanEngineWeb()
        engine.delegate = nil
    }

    // MARK: - Callbacks to be overridden by Subclasses

    /// Called when the state changes to `.displayed`.
    /// Subclasses decide how to actually show the UI (inline or modal).
    open func onMessageDisplayed() {
        // Subclasses can override to do modal or inline show
    }

    /// Called when the message is dismissed (or reset). Subclasses decide
    /// how to handle the cleanup animation or removal.
    func onMessageDismissed(messageState: MessageState) {
        // Subclasses can override
    }

    // MARK: - EngineWebDelegate

    public func bootstrapped() {
        logger.logWithModuleTag("Bourbon Engine bootstrapped", level: .debug)
        // (Optional) If empty message ID, clean engine
        if currentMessage.messageId.isEmpty {
            engine.cleanEngineWeb()
        }
    }

    public func tap(name: String, action: String, system: Bool) {
        logger.logWithModuleTag("Action triggered: \(action) with name: \(name)", level: .info)
        inAppMessageManager.dispatch(action: .engineAction(
            action: .tap(message: currentMessage, route: currentRoute, name: name, action: action)
        ))
        gistView.delegate?.action(
            message: currentMessage,
            currentRoute: currentRoute,
            action: action,
            name: name
        )

        guard let url = URL(string: action), url.scheme == "gist" else {
            // Non-gist actions (deep links, system actions, etc.)
            handleNonGistAction(action, system: system)
            return
        }

        switch url.host {
        case "close":
            logger.logWithModuleTag("Dismissing from action: \(action)", level: .info)
            inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage, viaCloseAction: true))
        case "loadPage":
            // ...
            let encodedUrl = URL(string: action.percentEncode(character: "#")) ?? url
            if let page = encodedUrl.queryParameters?["url"],
               let pageUrl = URL(string: page),
               UIApplication.shared.canOpenURL(pageUrl) {
                UIApplication.shared.open(pageUrl)
            }
        case "showMessage":
            if currentMessage.isEmbedded {
                showNewMessage(url: url)
            } else {
                inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage, shouldLog: false))
                showNewMessage(url: url)
            }
        default:
            break
        }
    }

    // For non-gist actions (e.g., universal links or custom schemes)
    private func handleNonGistAction(_ action: String, system: Bool) {
        if system {
            inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage, shouldLog: false))
            if let url = URL(string: action), UIApplication.shared.canOpenURL(url) {
                // Attempt to open with NSUserActivity for universal link
                let handledByUserActivity = continueNSUserActivity(webpageURL: url)
                if !handledByUserActivity {
                    // Fallback: open directly if userActivity wasn't handled
                    UIApplication.shared.open(url) { handled in
                        if handled {
                            self.logger.logWithModuleTag("Dismissing from system action: \(action)", level: .info)
                        } else {
                            self.logger.logWithModuleTag("System action not handled", level: .info)
                        }
                    }
                } else {
                    logger.logWithModuleTag("Handled by NSUserActivity", level: .info)
                }
            }
        }
    }

    public func continueNSUserActivity(webpageURL: URL) -> Bool {
        guard #available(iOS 10.0, *) else {
            return false
        }
        guard isLinkValidNSUserActivityLink(webpageURL) else {
            return false
        }

        let openLinkInHostAppActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        openLinkInHostAppActivity.webpageURL = webpageURL

        let didHostAppHandleLink = UIApplication.shared.delegate?.application?(
            UIApplication.shared,
            continue: openLinkInHostAppActivity,
            restorationHandler: { _ in }
        ) ?? false

        return didHostAppHandleLink
    }

    public func isLinkValidNSUserActivityLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme else {
            return false
        }
        return ["http", "https"].contains(scheme)
    }

    public func routeChanged(newRoute: String) {
        logger.info("Message route changed to: \(newRoute)")
    }

    public func sizeChanged(width: CGFloat, height: CGFloat) {
        // Subclass might or might not override.
        // Also call gistView.delegate if needed.
        gistView.delegate?.sizeChanged(message: currentMessage, width: width, height: height)
        logger.logWithModuleTag("Message size changed Width: \(width) - Height: \(height)", level: .debug)
    }

    public func routeError(route: String) {
        logger.logWithModuleTag("Error loading message with route: \(route)", level: .error)
        inAppMessageManager.dispatch(
            action: .engineAction(action: .messageLoadingFailed(message: currentMessage))
        )
    }

    public func error() {
        logger.logWithModuleTag("Error loading message with id: \(currentMessage.describeForLogs)", level: .error)
        inAppMessageManager.dispatch(
            action: .engineAction(action: .messageLoadingFailed(message: currentMessage))
        )
    }

    public func routeLoaded(route: String) {
        logger.logWithModuleTag("Message loaded with route: \(route)", level: .info)

        currentRoute = route
        if route == currentMessage.messageId, !isMessageLoaded {
            isMessageLoaded = true
            // If embedded, always show. Otherwise, check app state
            if isMessageEmbed {
                inAppMessageManager.dispatch(action: .displayMessage(message: currentMessage))
            } else {
                if UIApplication.shared.applicationState == .active {
                    inAppMessageManager.dispatch(action: .displayMessage(message: currentMessage))
                } else {
                    inAppMessageManager.dispatch(
                        action: .dismissMessage(message: currentMessage, shouldLog: false, viaCloseAction: false)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    public func showNewMessage(url: URL) {
        logger.logWithModuleTag("Showing new message from action: \(url.absoluteString)", level: .info)
        var properties: [String: Any]?

        if let stringProps = url.queryParameters?["properties"],
           let decodedData = Data(base64Encoded: stringProps),
           let decodedString = String(data: decodedData, encoding: .utf8),
           let convertedProps = convertToDictionary(text: decodedString) {
            properties = convertedProps
        }

        if let messageId = url.queryParameters?["messageId"] {
            let message = Message(messageId: messageId, properties: properties)
            inAppMessageManager.dispatch(action: .loadMessage(message: message))
        }
    }

    public func convertToDictionary(text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
}
