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
    let gistView: GistView
    private var currentRoute: String
    private var elapsedTimer = ElapsedTimer()
    weak var delegate: GistDelegate?
    private let engineWebProvider: EngineWebProvider = DIGraphShared.shared.engineWebProvider
    private var deeplinkUtil: DeepLinkUtil = DIGraphShared.shared.deepLinkUtil

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
        self.gistView = GistView(message: currentMessage, engineView: engine.view)
        engine.delegate = self
    }

    deinit {
        self.stopAndCleanup()
    }

    // The manager instance is no longer needed. Create a new instance when you want to display another message.
    // Note: This function does not remove the WebView from the view hierarchy. Do that from the UI layer.
    func stopAndCleanup() {
        // First, stop sending events to the delegates.
        delegate = nil
        gistView.delegate = nil

        // Then, cleanup resources.
        engine.cleanEngineWeb()
    }

    // MARK: event listeners that subclasses override to handle events.

    // Called when close action button pressed.
    func onCloseAction() {
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
        // This condition executes only for modal messages and not inline messages.
        // For inline messages, it prevents duplicate tracking and avoids making multiple event listener calls to delegate methods.
        if currentMessage.isModalMessage {
            delegate?.action(message: currentMessage, currentRoute: currentRoute, action: action, name: name, shouldTrackMetric: true)
        }
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
                if let url = URL(string: action) {
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
                    deeplinkUtil.handleDeepLink(url)
                    onDeepLinkOpened()
                }
            }
        }
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
