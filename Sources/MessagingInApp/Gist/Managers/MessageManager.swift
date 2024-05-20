import Foundation
import UIKit

public enum GistMessageActions: String {
    case close = "gist://close"
}

/**
 Class that implements the business logic for a inline message being displayed.
 */
class InlineMessageManager: MessageManager {}

/**
 Class that implements the business logic for a modal message being displayed.
 */
class ModalMessageManager: MessageManager {
    private var messageLoaded = false
    private var modalViewManager: ModalViewManager?
    var messagePosition: MessagePosition = .top

    override func routeLoaded(route: String) {
        super.routeLoaded(route: route)

        if route == currentMessage.messageId, !messageLoaded {
            messageLoaded = true
            if isMessageEmbed {
                delegate?.messageShown(message: currentMessage)
            } else {
                if UIApplication.shared.applicationState == .active {
                    loadModalMessage()
                } else {
                    Gist.shared.removeMessageManager(instanceId: currentMessage.instanceId)
                }
            }
        }
    }

    func showMessage(position: MessagePosition) {
        startLoadingMessage()
        messagePosition = position
    }

    override func dismissMessage(completionHandler: (() -> Void)? = nil) {
        if let modalViewManager = modalViewManager {
            modalViewManager.dismissModalView { [weak self] in
                guard let self = self else { return }
                self.delegate?.messageDismissed(message: self.currentMessage)
                completionHandler?()
            }
        }
    }

    private func loadModalMessage() {
        if messageLoaded {
            modalViewManager = ModalViewManager(gistView: gistView, position: messagePosition)
            modalViewManager?.showModalView { [weak self] in
                guard let self = self else { return }
                self.delegate?.messageShown(message: self.currentMessage)
                self.doneLoadingMessage()
            }
        }
    }
}

/**
 Class that handles a lot of the business logic for modal and inline in-app messages.

 This class is meant to be extended and not constructed directly. It holds the common logic between all in-app message types.

 Usage:
 * When you have a Message that should be displayed, create a new instance of manager. You create 1 manager instance per 1 in-app message to display:
 ```
 // Keep a strong reference to manager instance.
 let messageManager = MessageManager(siteId: Gist.shared.siteId, message: message)
 ```
 * Get the WebView instance that displays the in-app message: `messageManager.gistView`
 * Set the delegate to listen for events from the WebView: `messageManager.gistView.delegate = self`
 * Display the WebView in your view: `addSubview(messageManager.gistView)`
 */
class MessageManager: EngineWebDelegate {
    private var engine: EngineWeb?
    private let siteId: String
    var isMessageEmbed = false
    let currentMessage: Message
    var gistView: GistView!
    private var currentRoute: String
    private var elapsedTimer = ElapsedTimer()
    weak var delegate: GistDelegate?

    init(siteId: String, message: Message) {
        self.siteId = siteId
        self.currentMessage = message
        self.currentRoute = message.messageId

        let engineWebConfiguration = EngineWebConfiguration(
            siteId: Gist.shared.siteId,
            dataCenter: Gist.shared.dataCenter,
            instanceId: message.instanceId,
            endpoint: Settings.Network.engineAPI,
            messageId: message.messageId,
            properties: message.toEngineRoute().properties
        )

        self.engine = EngineWeb(configuration: engineWebConfiguration)
        if let engine = engine {
            engine.delegate = self
            self.gistView = GistView(message: currentMessage, engineView: engine.view)
        }
    }

    // MARK: Timer determining how long message took to load.

    // The manager subclasses are expected to call these functions to determine how long the messages took to load.

    func startLoadingMessage() {
        elapsedTimer.start(title: "Loading message with id: \(currentMessage.messageId)")
    }

    func doneLoadingMessage() {
        elapsedTimer.end()
    }

    func getMessageView() -> GistView {
        isMessageEmbed = true
        return gistView
    }

    func dismissMessage(completionHandler: (() -> Void)? = nil) {
        // expect subclass implements this.
    }

    func removePersistentMessage() {
        if currentMessage.gistProperties.persistent == true {
            Logger.instance.debug(message: "Persistent message dismissed, logging view")
            Gist.shared.logMessageView(message: currentMessage)
        }
    }

    func bootstrapped() {
        Logger.instance.debug(message: "Bourbon Engine bootstrapped")

        // Cleaning after engine web is bootstrapped and all assets downloaded.
        if currentMessage.messageId == "" {
            engine?.cleanEngineWeb()
        }
    }

    // swiftlint:disable cyclomatic_complexity
    func tap(name: String, action: String, system: Bool) {
        Logger.instance.info(message: "Action triggered: \(action) with name: \(name)")
        delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name)
        gistView.delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name)

        if let url = URL(string: action), url.scheme == "gist" {
            switch url.host {
            case "close":
                Logger.instance.info(message: "Dismissing from action: \(action)")
                removePersistentMessage()
                dismissMessage()
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
                    dismissMessage {
                        self.showNewMessage(url: url)
                    }
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
                                Logger.instance.info(message: "Dismissing from system action: \(action)")
                                self.dismissMessage()
                            } else {
                                Logger.instance.info(message: "System action not handled")
                            }
                        }
                    } else {
                        Logger.instance.info(message: "Handled by NSUserActivity")
                        dismissMessage()
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
        Logger.instance.info(message: "Message route changed to: \(newRoute)")
    }

    func sizeChanged(width: CGFloat, height: CGFloat) {
        gistView.delegate?.sizeChanged(message: currentMessage, width: width, height: height)
        Logger.instance.debug(message: "Message size changed Width: \(width) - Height: \(height)")
    }

    func routeError(route: String) {
        Logger.instance.error(message: "Error loading message with route: \(route)")
        delegate?.messageError(message: currentMessage)
    }

    func error() {
        Logger.instance.error(message: "Error loading message with id: \(currentMessage.messageId)")
        delegate?.messageError(message: currentMessage)
    }

    func routeLoaded(route: String) {
        Logger.instance.info(message: "Message loaded with route: \(route)")

        currentRoute = route
    }

    deinit {
        engine?.cleanEngineWeb()
        engine = nil
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
            _ = Gist.shared.showMessage(Message(messageId: messageId, properties: properties))
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
