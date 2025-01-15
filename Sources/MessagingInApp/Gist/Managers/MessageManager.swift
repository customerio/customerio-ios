import CioInternalCommon
// MessageManagerType.swift
import Foundation
import UIKit

/// Protocol defining the core functionality that all message managers must implement
protocol MessageManagerDelegate: AnyObject {
    func messageShown(message: Message)
    func messageDismissed(message: Message)
    func messageError(message: Message)
    func action(message: Message, currentRoute: String, action: String, name: String)
}

public enum GistMessageActions: String {
    case close = "gist://close"
}

protocol MessageManager {
    var currentMessage: Message { get }
    var currentRoute: String { get }
    var gistView: GistView { get }
    var delegate: MessageManagerDelegate? { get set }

    func handleAction(name: String, action: String, system: Bool)
    func handleRouteChange(_ route: String)
    func cleanup()
    func handleMessageLoaded()

    // Protected methods for subclasses
    func onDeepLinkOpened()
    func onTapAction(message: Message, currentRoute: String, action: String, name: String)
}

// BaseMessageManager.swift
class BaseMessageManager: MessageManager {
    // MARK: - Properties

    private let logger: Logger
    private let threadUtil: ThreadUtil
    private let gist: GistProvider

    weak var delegate: MessageManagerDelegate?

    let currentMessage: Message
    private(set) var currentRoute: String
    var engine: EngineWebInstance
    let gistView: GistView
    let inAppMessageManager: InAppMessageManager

    @Atomic private var isMessageLoaded: Bool = false
    private var inAppMessageStoreSubscriber: InAppMessageStoreSubscriber?
    private var elapsedTimer = ElapsedTimer()

    // MARK: - Initialization

    init(state: InAppMessageState, message: Message) {
        self.currentMessage = message
        self.currentRoute = message.messageId

        let diGraph = DIGraphShared.shared
        self.logger = diGraph.logger
        self.inAppMessageManager = diGraph.inAppMessageManager
        self.threadUtil = diGraph.threadUtil
        self.gist = diGraph.gistProvider

        let engineWebConfiguration = EngineWebConfiguration(
            siteId: state.siteId,
            dataCenter: state.dataCenter,
            instanceId: message.instanceId,
            endpoint: state.environment.networkSettings.engineAPI,
            messageId: message.messageId,
            properties: message.properties.mapValues { AnyEncodable($0) }
        )

        self.engine = diGraph.engineWebProvider.getEngineWebInstance(
            configuration: engineWebConfiguration,
            state: state,
            message: message
        )
        self.gistView = GistView(message: currentMessage, engineView: engine.view)

        setupEngineDelegate()
        subscribeToInAppMessageState()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    func cleanup() {
        unsubscribeFromInAppMessageState()
        removeEngineWebView()
    }

    func handleMessageLoaded() {
        // Base implementation - override in subclasses
        logger.logWithModuleTag("Message loaded: \(currentMessage.describeForLogs)", level: .debug)
    }

    func handleAction(name: String, action: String, system: Bool) {
        logger.logWithModuleTag("Action triggered: \(action) with name: \(name)", level: .info)
        processAction(name: name, action: action, system: system)
    }

    func handleRouteChange(_ route: String) {
        currentRoute = route
        logger.logWithModuleTag("Route changed to: \(route)", level: .info)
    }

    // MARK: - Protected Methods for Subclasses

    func dismissMessage(completion: (() -> Void)? = nil) {
        inAppMessageManager.dispatch(action: .dismissMessage(message: currentMessage))
        completion?()
    }

    func onDeepLinkOpened() {
        // Base implementation - can be overridden by subclasses
        logger.logWithModuleTag("Deep link opened", level: .debug)
    }

    func onReplaceMessage(newMessageToShow: Message) {
        // Base implementation - should be overridden by subclasses
        logger.logWithModuleTag("Replace message requested", level: .debug)
    }

    func onTapAction(message: Message, currentRoute: String, action: String, name: String) {
        // Base implementation - can be overridden by subclasses
        logger.logWithModuleTag("Tap action received", level: .debug)
    }

    // MARK: - Private Methods

    private func setupEngineDelegate() {
        engine.delegate = self
    }
}

// MARK: - EngineWebDelegate

extension BaseMessageManager: EngineWebDelegate {
    func bootstrapped() {
        logger.logWithModuleTag("Bourbon Engine bootstrapped", level: .debug)

        // Clean up if empty message id
        if currentMessage.messageId.isEmpty {
            engine.cleanEngineWeb()
        }
    }

    func routeLoaded(route: String) {
        logger.logWithModuleTag("Message loaded with route: \(route)", level: .info)
        currentRoute = route

        // Only handle message loading once
        if route == currentMessage.messageId, !isMessageLoaded {
            isMessageLoaded = true
            handleMessageLoaded()
        }
    }

    func routeError(route: String) {
        logger.logWithModuleTag("Error loading message with route: \(route)", level: .error)
        inAppMessageManager.dispatch(action: .engineAction(action: .messageLoadingFailed(message: currentMessage)))
    }

    func error() {
        logger.logWithModuleTag("Error loading message with id: \(currentMessage.describeForLogs)", level: .error)
        inAppMessageManager.dispatch(action: .engineAction(action: .messageLoadingFailed(message: currentMessage)))
    }

    func sizeChanged(width: CGFloat, height: CGFloat) {
        logger.logWithModuleTag("Message size changed Width: \(width) - Height: \(height)", level: .debug)
        gistView.delegate?.sizeChanged(message: currentMessage, width: width, height: height)

        // Let inline messages handle size changes specially
        if let inlineManager = self as? InlineMessageManager {
            inlineManager.sizeChanged(message: currentMessage, width: width, height: height)
        }
    }

    func tap(name: String, action: String, system: Bool) {
        handleAction(name: name, action: action, system: system)
    }

    func routeChanged(newRoute: String) {
        handleRouteChange(newRoute)
    }

    private func subscribeToInAppMessageState() {
        inAppMessageStoreSubscriber = {
            let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                self?.handleStateChange(state)
            }
            inAppMessageManager.subscribe(keyPath: \.currentMessageState, subscriber: subscriber)
            return subscriber
        }()
    }

    private func unsubscribeFromInAppMessageState() {
        guard let subscriber = inAppMessageStoreSubscriber else { return }
        logger.logWithModuleTag("Unsubscribing from InAppMessageState", level: .debug)
        inAppMessageManager.unsubscribe(subscriber: subscriber)
        inAppMessageStoreSubscriber = nil
    }

    private func removeEngineWebView() {
        guard engine.delegate != nil else { return }
        logger.logWithModuleTag("Cleaning EngineWebView", level: .debug)
        engine.cleanEngineWeb()
        engine.delegate = nil
    }

    private func handleStateChange(_ state: InAppMessageState) {
        threadUtil.runMain { [weak self] in
            switch state.currentMessageState {
            case .displayed:
                self?.handleMessageDisplayed()
            case .dismissed, .initial:
                self?.handleMessageDismissed()
            default:
                break
            }
        }
    }

    private func handleMessageDisplayed() {
        handleMessageLoaded()
    }

    private func handleMessageDismissed() {
        cleanup()
        gist.fetchUserMessagesFromRemoteQueue()
    }

    private func processAction(name: String, action: String, system: Bool) {
        inAppMessageManager.dispatch(action: .engineAction(action: .tap(
            message: currentMessage,
            route: currentRoute,
            name: name,
            action: action
        )))

        if let url = URL(string: action) {
            handleActionURL(url, name: name, system: system)
        }
    }

    private func handleActionURL(_ url: URL, name: String, system: Bool) {
        if url.scheme == "gist" {
            handleGistAction(url)
        } else if system {
            handleSystemAction(url)
        }
    }

    private func handleGistAction(_ url: URL) {
        switch url.host {
        case "close":
            logger.logWithModuleTag("Dismissing from action: \(url.absoluteString)", level: .info)
            dismissMessage()

        case "loadPage":
            if let page = url.queryParameters?["url"],
               let pageUrl = URL(string: page),
               UIApplication.shared.canOpenURL(pageUrl) {
                UIApplication.shared.open(pageUrl)
            }

        case "showMessage":
            handleShowNewMessage(url: url)

        default:
            break
        }
    }

    private func handleSystemAction(_ url: URL) {
        guard UIApplication.shared.canOpenURL(url) else { return }

        // First try universal links through NSUserActivity
        let handledByUserActivity = continueNSUserActivity(webpageURL: url)

        if !handledByUserActivity {
            // Fallback to direct URL opening
            UIApplication.shared.open(url) { [weak self] handled in
                if handled {
                    self?.logger.logWithModuleTag("Opened system URL: \(url.absoluteString)", level: .info)
                } else {
                    self?.logger.logWithModuleTag("Failed to open system URL", level: .info)
                }
            }
        }
    }

    private func continueNSUserActivity(webpageURL: URL) -> Bool {
        guard #available(iOS 10.0, *),
              isValidUserActivityLink(webpageURL)
        else {
            return false
        }

        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = webpageURL

        return UIApplication.shared.delegate?.application?(
            UIApplication.shared,
            continue: activity,
            restorationHandler: { _ in }
        ) ?? false
    }

    private func isValidUserActivityLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme else { return false }
        return ["http", "https"].contains(scheme)
    }

    private func handleShowNewMessage(url: URL) {
        var properties: [String: Any]?

        // Decode properties if present
        if let stringProps = url.queryParameters?["properties"],
           let decodedData = Data(base64Encoded: stringProps),
           let decodedString = String(data: decodedData, encoding: .utf8),
           let convertedProps = convertToDictionary(text: decodedString) {
            properties = convertedProps
        }

        // Create and load new message if ID present
        if let messageId = url.queryParameters?["messageId"] {
            let message = Message(messageId: messageId, properties: properties)

            // For inline messages, just replace. For modal, dismiss first
            if currentMessage.isEmbedded {
                inAppMessageManager.dispatch(action: .loadMessage(message: message))
            } else {
                dismissMessage { [weak self] in
                    self?.inAppMessageManager.dispatch(action: .loadMessage(message: message))
                }
            }
        }
    }

    private func convertToDictionary(text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }

        do {
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            logger.logWithModuleTag("Failed to parse JSON: \(error)", level: .error)
            return nil
        }
    }
}
