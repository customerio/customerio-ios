import CioInternalCommon
import Foundation
import UIKit
import WebKit

public protocol EngineWebDelegate: AnyObject {
    func bootstrapped()
    func tap(name: String, action: String, system: Bool)
    func routeChanged(newRoute: String)
    func routeError(route: String)
    func routeLoaded(route: String)
    func sizeChanged(width: CGFloat, height: CGFloat)
    func error()
}

protocol EngineWebInstance: AutoMockable {
    var delegate: EngineWebDelegate? { get set }
    var view: UIView { get }
    func cleanEngineWeb()
}

public class EngineWeb: NSObject, EngineWebInstance {
    private let logger: Logger = DIGraphShared.shared.logger
    private let inAppMessageManager: InAppMessageManager = DIGraphShared.shared.inAppMessageManager
    private let currentMessage: Message
    private var _currentRoute = ""
    private var _timeoutTimer: Timer?
    private var _elapsedTimer = ElapsedTimer()

    public weak var delegate: EngineWebDelegate?
    var webView = WKWebView()

    public var view: UIView {
        webView
    }

    private let currentConfiguration: EngineWebConfiguration

    public private(set) var currentRoute: String {
        get { _currentRoute }
        set { _currentRoute = newValue }
    }

    /// Initializes the EngineWeb instance with the given configuration, state, and message.
    init(configuration: EngineWebConfiguration, state: InAppMessageState, message: Message) {
        self.currentMessage = message
        self.currentConfiguration = configuration

        super.init()

        setupWebView()
        injectJavaScriptListener()
        loadMessage(with: state)
    }

    /// Sets up the properties and appearance of the WKWebView.
    private func setupWebView() {
        _elapsedTimer.start(title: "Engine render for message: \(currentConfiguration.messageId)")

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    /// Injects a JavaScript listener to handle messages from the web content.
    private func injectJavaScriptListener() {
        let js = """
        window.addEventListener('message', function(event) {
            webkit.messageHandlers.gist.postMessage(event.data);
        });
        """
        let messageHandlerScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)

        webView.configuration.userContentController.add(self, name: "gist")
        webView.configuration.userContentController.addUserScript(messageHandlerScript)
    }

    private func loadMessage(with state: InAppMessageState) {
        let messageUrl = "\(state.environment.networkSettings.renderer)/index.html"
        logger.logWithModuleTag("Rendering message with URL: \(messageUrl)", level: .debug)

        if let url = URL(string: messageUrl) {
            _timeoutTimer?.invalidate()
            _timeoutTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(forcedTimeout), userInfo: nil, repeats: false)
            webView.load(URLRequest(url: url))
        } else {
            logger.logWithModuleTag("Invalid URL: \(messageUrl)", level: .error)
            delegate?.error()
        }
    }

    public func cleanEngineWeb() {
        _timeoutTimer?.invalidate()
        _timeoutTimer = nil
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gist")
    }

    @objc
    func forcedTimeout() {
        logger.logWithModuleTag("Timeout triggered, triggering message error.", level: .info)
        inAppMessageManager.dispatch(action: .engineAction(action: .messageLoadingFailed(message: currentMessage)))
        delegate?.error()
    }
}

// swiftlint:disable cyclomatic_complexity
extension EngineWeb: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: AnyObject],
              let eventProperties = dict["gist"] as? [String: AnyObject],
              let method = eventProperties["method"] as? String,
              let engineEventMethod = EngineEvent(rawValue: method)
        else {
            return
        }

        handleEngineEvent(engineEventMethod, eventProperties: eventProperties)
    }

    private func handleEngineEvent(_ engineEventMethod: EngineEvent, eventProperties: [String: AnyObject]) {
        switch engineEventMethod {
        case .bootstrapped:
            _timeoutTimer?.invalidate()
            _timeoutTimer = nil
            delegate?.bootstrapped()
        case .routeLoaded:
            _elapsedTimer.end()
            if let route = EngineEventHandler.getRouteLoadedProperties(properties: eventProperties) {
                delegate?.routeLoaded(route: route)
            }
        case .routeChanged:
            if let route = EngineEventHandler.getRouteChangedProperties(properties: eventProperties) {
                _elapsedTimer.start(title: "Engine render for message: \(route)")
                delegate?.routeChanged(newRoute: route)
            }
        case .routeError:
            if let route = EngineEventHandler.getRouteErrorProperties(properties: eventProperties) {
                delegate?.routeError(route: route)
            }
        case .sizeChanged:
            if let size = EngineEventHandler.getSizeProperties(properties: eventProperties) {
                delegate?.sizeChanged(width: size.width, height: size.height)
            }
        case .tap:
            if let tapProperties = EngineEventHandler.getTapProperties(properties: eventProperties) {
                delegate?.tap(name: tapProperties.name, action: tapProperties.action, system: tapProperties.system)
            }
        case .error:
            delegate?.error()
        }
    }
}

// swiftlint:enable cyclomatic_complexity
extension EngineWeb: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectConfiguration(currentConfiguration)
    }

    private func injectConfiguration(_ configuration: EngineWebConfiguration) {
        do {
            let jsonData = try JSONEncoder().encode(["options": configuration])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw NSError(domain: "EngineWeb", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JSON string"])
            }

            let js = "window.postMessage(\(jsonString), '*');"

            webView.evaluateJavaScript(js) { [weak self] _, error in
                if let error = error {
                    self?.logger.logWithModuleTag("JavaScript execution error: \(error)", level: .error)
                    self?.delegate?.error()
                } else {
                    self?.logger.logWithModuleTag("Configuration injected successfully", level: .error)
                }
            }
        } catch {
            logger.logWithModuleTag("Failed to encode configuration: \(error)", level: .error)
            delegate?.error()
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        delegate?.error()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.error()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        delegate?.error()
    }
}
