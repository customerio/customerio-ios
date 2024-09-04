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

    private let currentMessage: Message
    private var currentRoute: String
    private let isMessageEmbed: Bool
    private var messagePosition: MessagePosition = .center

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
        self.engineWebProvider = diGraph.engineWebProvider

        let engineWebConfiguration = EngineWebConfiguration(
            siteId: state.siteId,
            dataCenter: state.dataCenter,
            instanceId: message.instanceId,
            endpoint: state.environment.networkSettings.engineAPI,
            messageId: message.messageId,
            properties: message.toEngineRoute().properties
        )

        self.engine = engineWebProvider.getEngineWebInstance(configuration: engineWebConfiguration, state: state)
        engine.delegate = self
        self.gistView = GistView(message: currentMessage, engineView: engine.view)

        subscribeToInAppMessageState()
    }

    func subscribeToInAppMessageState() {
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [self] state in
                switch state.currentMessageState {
                case .displayed:
                    threadUtil.runMain {
                        self.loadModalMessage()
                    }

                case .dismissed:
                    threadUtil.runMain {
                        self.engine.delegate = nil
                        self.dismissMessage()
                        self.inAppMessageStoreSubscriber = nil
                    }

                default:
                    break
                }
            }
            inAppMessageManager.subscribe(keyPath: \.currentMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    func showMessage(position: MessagePosition) {
        elapsedTimer.start(title: "Displaying modal for message: \(currentMessage.messageId)")
        messagePosition = position
    }

    private func loadModalMessage() {
        modalViewManager = ModalViewManager(gistView: gistView, position: messagePosition)
        modalViewManager?.showModalView { [weak self] in
            guard let self = self else { return }

            self.elapsedTimer.end()
        }
    }

    private func dismissMessage(completionHandler: (() -> Void)? = nil) {
        if let modalViewManager = modalViewManager {
            modalViewManager.dismissModalView { [weak self] in
                guard let _ = self else { return }

                completionHandler?()
            }
        }
    }

    func bootstrapped() {
        logger.debug("Bourbon Engine bootstrapped")

        // Cleaning after engine web is bootstrapped and all assets downloaded.
        if currentMessage.messageId == "" {
            engine.cleanEngineWeb()
        }
    }

    // swiftlint:disable cyclomatic_complexity
    func tap(name: String, action: String, system: Bool) {
        logger.info("Action triggered: \(action) with name: \(name)")
        inAppMessageManager.dispatch(action: .engineAction(action: .tap(message: currentMessage, route: currentRoute, name: name, action: action)))
        gistView.delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name)

        if let url = URL(string: action), url.scheme == "gist" {
            switch url.host {
            case "close":
                logger.info("Dismissing from action: \(action)")
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
                                self.logger.info("Dismissing from system action: \(action)")
                                self.inAppMessageManager.dispatch(action: .dismissMessage(message: self.currentMessage, shouldLog: false))
                            } else {
                                self.logger.info("System action not handled")
                            }
                        }
                    } else {
                        logger.info("Handled by NSUserActivity")
                        inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage))
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
        logger.debug("Message size changed Width: \(width) - Height: \(height)")
    }

    func routeError(route: String) {
        logger.error("Error loading message with route: \(route)")
        inAppMessageManager.dispatch(action: .engineAction(action: .messageLoadingFailed(message: currentMessage)))
    }

    func error() {
        logger.error("Error loading message with id: \(currentMessage.messageId)")
        inAppMessageManager.dispatch(action: .engineAction(action: .error(message: currentMessage)))
    }

    func routeLoaded(route: String) {
        logger.info("Message loaded with route: \(route)")

        currentRoute = route
        if route == currentMessage.messageId {
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

    deinit {
        if let subscriber = inAppMessageStoreSubscriber {
            inAppMessageManager.unsubscribe(subscriber: subscriber)
        }
        inAppMessageStoreSubscriber = nil
        engine.cleanEngineWeb()
    }

    private func showNewMessage(url: URL) {
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
