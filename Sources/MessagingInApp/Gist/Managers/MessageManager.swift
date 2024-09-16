import CioInternalCommon
import Foundation
import UIKit

public enum GistMessageActions: String {
    case close = "gist://close"
}

class MessageManager: EngineWebDelegate {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let threadUtil: ThreadUtil
    private let gist: GistProvider

    private let currentMessage: Message
    private var currentRoute: String
    private let isMessageEmbed: Bool

    @Atomic private var isMessageLoaded: Bool = false
    private var inAppMessageStoreSubscriber: InAppMessageStoreSubscriber?
    private var elapsedTimer = ElapsedTimer()
    private var modalViewManager: ModalViewManager?
    private var engine: EngineWebInstance!
    private var gistView: GistView!
    private let engineWebProvider: EngineWebProvider

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

        let engineWebConfiguration = EngineWebConfiguration(
            siteId: state.siteId,
            dataCenter: state.dataCenter,
            instanceId: message.instanceId,
            endpoint: state.environment.networkSettings.engineAPI,
            messageId: message.messageId,
            properties: message.properties.mapValues { AnyEncodable($0) }
        )

        self.engine = engineWebProvider.getEngineWebInstance(configuration: engineWebConfiguration, state: state, message: message)
        engine.delegate = self
        self.gistView = GistView(message: currentMessage, engineView: engine.view)

        subscribeToInAppMessageState()
    }

    deinit {
        unsubscribeFromInAppMessageState()
        removeEngineWebView()
    }

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
                        self.loadModalMessage()
                    }

                // Dismiss the message when the message is dismissed or initial state
                // Initial state may only be received when state is reset while a message was being displayed
                case .dismissed, .initial:
                    threadUtil.runMain {
                        // Unsubscribe from InAppMessageState when the message is dismissed completely
                        // so that MessageManager is deallocated only after dismiss animation is completed.
                        self.dismissMessage {
                            self.removeEngineWebView()
                            self.unsubscribeFromInAppMessageState()
                            // Fetch user messages from local store after message is dismissed so that
                            // next message can be displayed instantly if available.
                            // This is only needed when message is dismissed and not when it is reset.
                            if case .dismissed = messageState {
                                self.gist.fetchUserMessagesFromRemoteQueue()
                            }
                        }
                    }

                default:
                    break
                }
            }
            inAppMessageManager.subscribe(keyPath: \.currentMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    /// Unsubscribes from InAppMessageState so that MessageManager can be deallocated.
    func unsubscribeFromInAppMessageState() {
        guard let subscriber = inAppMessageStoreSubscriber else { return }

        logger.logWithModuleTag("Unsubscribing MessageManager from InAppMessageState", level: .debug)
        inAppMessageManager.unsubscribe(subscriber: subscriber)
        inAppMessageStoreSubscriber = nil
    }

    /// Removes EngineWebView from MessageManager and sets the delegate to nil to stop receiving JS events.
    func removeEngineWebView() {
        // If delegate is nil, then EngineWebView is already cleaned up.
        guard let _ = engine.delegate else { return }

        logger.logWithModuleTag("Cleaning EngineWebView from MessageManager", level: .debug)
        engine.cleanEngineWeb()
        engine.delegate = nil
    }

    func showMessage() {
        elapsedTimer.start(title: "Displaying modal for message: \(currentMessage.messageId)")
    }

    private func loadModalMessage() {
        guard isMessageLoaded else {
            logger.logWithModuleTag("Message already loaded. Skipping loading modal message: \(currentMessage.describeForLogs)", level: .debug)
            return
        }

        logger.logWithModuleTag("Loading modal message: \(currentMessage.describeForLogs)", level: .debug)
        modalViewManager = ModalViewManager(gistView: gistView, position: currentMessage.gistProperties.position)
        modalViewManager?.showModalView { [weak self] in
            guard let self = self else { return }

            self.elapsedTimer.end()
        }
    }

    private func dismissMessage(completionHandler: (() -> Void)? = nil) {
        logger.logWithModuleTag("Dismissing message: \(currentMessage.describeForLogs) from MessageManager", level: .debug)
        // If modalViewManager is nil, skip dismissing the message but call completion handler so rest of the resources can be cleaned up.
        guard let modalViewManager = modalViewManager else {
            completionHandler?()
            return
        }
        // Dismiss modal view and call the completion handler when modal view is dismissed.
        modalViewManager.dismissModalView { [weak self] in
            guard let _ = self else { return }

            completionHandler?()
        }
    }

    func bootstrapped() {
        logger.logWithModuleTag("Bourbon Engine bootstrapped", level: .debug)

        // Cleaning after engine web is bootstrapped and all assets downloaded.
        if currentMessage.messageId == "" {
            engine.cleanEngineWeb()
        }
    }

    // swiftlint:disable cyclomatic_complexity
    func tap(name: String, action: String, system: Bool) {
        logger.logWithModuleTag("Action triggered: \(action) with name: \(name)", level: .info)
        inAppMessageManager.dispatch(action: .engineAction(action: .tap(message: currentMessage, route: currentRoute, name: name, action: action)))
        gistView.delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name)

        if let url = URL(string: action), url.scheme == "gist" {
            switch url.host {
            case "close":
                logger.logWithModuleTag("Dismissing from action: \(action)", level: .info)
                inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage, viaCloseAction: true))
            case "loadPage":
                if let page = url.queryParameters?["url"],
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
            default: break
            }
        } else {
            if system {
                inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage, shouldLog: false))
                if let url = URL(string: action), UIApplication.shared.canOpenURL(url) {
                    /*
                     There are 2 types of deep links:
                     1. Universal Links which give URL format of a webpage using `http://` or `https://`
                     2. App scheme which give URL format using a prototol other then `http://` or `https://`.

                     First, try to open the link inside of the host app. This is to keep compatability with Universal Links.
                     Learn more of edge case: https://github.com/customerio/customerio-ios/issues/262

                     Fallback to opening the URL through a sytem call if:
                     1. deep link is an app scheme URL
                     2. Customer has not implemented the correct function in their host app to handle universal link:
                     ```
                     func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool
                     ```
                     3. Customer returned `false` from ^^^ function.
                     */
                    let handledByUserActivity = continueNSUserActivity(webpageURL: url)

                    if !handledByUserActivity {
                        // If `continueNSUserActivity` could not handle the URL, try opening it directly.
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
    }

    // swiftlint:enable cyclomatic_complexity

    // Check if
    func continueNSUserActivity(webpageURL: URL) -> Bool {
        guard #available(iOS 10.0, *) else {
            return false
        }
        guard isLinkValidNSUserActivityLink(webpageURL) else {
            return false
        }

        let openLinkInHostAppActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        openLinkInHostAppActivity.webpageURL = webpageURL

        let didHostAppHandleLink = UIApplication.shared.delegate?.application?(UIApplication.shared, continue: openLinkInHostAppActivity, restorationHandler: { _ in }) ?? false

        return didHostAppHandleLink
    }

    // The NSUserActivity.webpageURL property permits only specific URL schemes. This function exists to validate the scheme and prevent potential exceptions due to incompatible URL formats.
    func isLinkValidNSUserActivityLink(_ url: URL) -> Bool {
        guard let schemeOfUrl = url.scheme else {
            return false
        }

        // Constants to hold allowed URL schemes
        let allowedSchemes = ["http", "https"]

        return allowedSchemes.contains(schemeOfUrl)
    }

    func routeChanged(newRoute: String) {
        logger.info("Message route changed to: \(newRoute)")
    }

    func sizeChanged(width: CGFloat, height: CGFloat) {
        gistView.delegate?.sizeChanged(message: currentMessage, width: width, height: height)
        logger.logWithModuleTag("Message size changed Width: \(width) - Height: \(height)", level: .debug)
    }

    func routeError(route: String) {
        logger.logWithModuleTag("Error loading message with route: \(route)", level: .error)
        inAppMessageManager.dispatch(action: .engineAction(action: .messageLoadingFailed(message: currentMessage)))
    }

    func error() {
        logger.logWithModuleTag("Error loading message with id: \(currentMessage.describeForLogs)", level: .error)
        inAppMessageManager.dispatch(action: .engineAction(action: .messageLoadingFailed(message: currentMessage)))
    }

    func routeLoaded(route: String) {
        logger.logWithModuleTag("Message loaded with route: \(route)", level: .info)

        currentRoute = route
        // If the route is the same as the current message and the message is not already loaded,
        // then display the message.
        if route == currentMessage.messageId, !isMessageLoaded {
            isMessageLoaded = true
            if isMessageEmbed {
                inAppMessageManager.dispatch(action: .displayMessage(message: currentMessage))
            } else {
                if UIApplication.shared.applicationState == .active {
                    inAppMessageManager.dispatch(action: .displayMessage(message: currentMessage))
                } else {
                    inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage, shouldLog: false, viaCloseAction: false))
                }
            }
        }
    }

    private func showNewMessage(url: URL) {
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

    private func convertToDictionary(text: String) -> [String: Any]? {
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
