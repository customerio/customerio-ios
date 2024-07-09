import CioInternalCommon
import Foundation
import UIKit

public enum GistMessageActions: String {
    case close = "gist://close"
}

/**
 Handles business logic for in-app message events such as loading messages and handling when action buttons are clicked.

 This class is meant to be extended and not constructed directly. It holds the common logic between all in-app message types.

 Usage:
 * Extend class.
 * Override any of the abstract functions in class to implement custom logic for when certain events happen. Depending on the type of message you are displaying, you may want to handle events differently.
 */
class MessageManager {
    var engine: EngineWebInstance
    private let siteId: String
    let currentMessage: Message
    var gistView: GistView!
    private var currentRoute: String
    private var elapsedTimer = ElapsedTimer()
    weak var delegate: GistDelegate?
    private let engineWebProvider: EngineWebProvider = DIGraphShared.shared.engineWebProvider

    init(siteId: String, message: Message) {
        self.siteId = siteId
        self.currentMessage = message
        self.currentRoute = message.templateId

        let engineWebConfiguration = EngineWebConfiguration(
            siteId: Gist.shared.siteId,
            dataCenter: Gist.shared.dataCenter,
            instanceId: message.instanceId,
            endpoint: Settings.Network.engineAPI,
            messageId: message.templateId,
            properties: message.toEngineRoute().properties
        )

        // When EngineWeb instance is constructed, it will begin the rendering process for the in-app message.
        // This means that the message begins the process of loading.
        // Start a timer that helps us determine how long a message took to load/render.
        elapsedTimer.start(title: "Loading message with id: \(currentMessage.templateId)")

        self.engine = engineWebProvider.getEngineWebInstance(configuration: engineWebConfiguration)
        engine.delegate = self
        self.gistView = GistView(message: currentMessage, engineView: engine.view)
    }

    deinit {
        engine.cleanEngineWeb()
    }

    // MARK: event listeners that subclasses override to handle events.

    // Called when close action button pressed.
    func onCloseAction() {
        // Expect subclass implements this.
    }

    func onInlineButtonAction(message: Message, currentRoute: String, action: String, name: String) {
        // Expect subclass implements this.
    }

    // Called when a deep link action button was clicked in a message and the SDK opened the deep link.
    func onDeepLinkOpened() {
        // expect subclass implements this.
    }

    // Called when the message has finished loading and the WebView is ready to display the message.
    func onDoneLoadingMessage(routeLoaded: String, onComplete: @escaping () -> Void) {
        // expect subclass implements this.
    }

    // Called when an action button is clicked and the action is to show a different in-app message.
    func onReplaceMessage(newMessageToShow: Message) {
        // subclass should implement
    }
}

// The main logic of this class is being the delegate for the EngineWeb instance.
// This class's delegate responsibilities are to run the logic that's common to all types of in-app messages and call the event listeners that subclasses override.
extension MessageManager: EngineWebDelegate {
    func bootstrapped() {
        Logger.instance.debug(message: "Bourbon Engine bootstrapped")

        // Cleaning after engine web is bootstrapped and all assets downloaded.
        if currentMessage.templateId == "" {
            engine.cleanEngineWeb()
        }
    }

    func tap(name: String, action: String, system: Bool) {
        Logger.instance.info(message: "Action triggered: \(action) with name: \(name)")
        delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name)
        gistView.delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name)

        if let url = URL(string: action), url.scheme == "gist" {
            switch url.host {
            case "close":
                Logger.instance.info(message: "Dismissing from action: \(action)")
                onCloseAction()
            case "loadPage":
                if let page = url.queryParameters?["url"],
                   let pageUrl = URL(string: page),
                   UIApplication.shared.canOpenURL(pageUrl) {
                    UIApplication.shared.open(pageUrl)
                }
            case "showMessage":
                showNewMessage(url: url)
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
                                self.onDeepLinkOpened()
                            } else {
                                Logger.instance.info(message: "System action not handled")
                            }
                        }
                    } else {
                        Logger.instance.info(message: "Handled by NSUserActivity")
                        onDeepLinkOpened()
                    }
                }
            }
        }
    }

    // Check if deep link can be handled in the host app. By using NSUserActivity, our SDK can handle Universal Links.
    private func continueNSUserActivity(webpageURL: URL) -> Bool {
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
    private func isLinkValidNSUserActivityLink(_ url: URL) -> Bool {
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
        Logger.instance.error(message: "Error loading message with id: \(currentMessage.templateId)")
        delegate?.messageError(message: currentMessage)
    }

    func routeLoaded(route: String) {
        Logger.instance.info(message: "Message loaded with route: \(route)")
        currentRoute = route

        onDoneLoadingMessage(routeLoaded: currentRoute) {
            self.delegate?.messageShown(message: self.currentMessage)
            self.elapsedTimer.end()
        }
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
            onReplaceMessage(newMessageToShow: Message(messageId: messageId, properties: properties))
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
