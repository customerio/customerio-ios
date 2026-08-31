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
    /// Called when a message fails to load or render, with the reason it failed.
    func error(_ error: InAppMessageError)
}

public extension EngineWebDelegate {
    /// Defaulted so conformers written against the reason-less callback keep compiling.
    func error(_ error: InAppMessageError) {
        self.error()
    }
}

protocol EngineWebInstance: AutoMockable {
    var delegate: EngineWebDelegate? { get set }
    var view: UIView { get }
    func cleanEngineWeb()
    func updateColorScheme(_ scheme: String)
}

public class EngineWeb: NSObject, EngineWebInstance {
    private let logger: Logger = DIGraphShared.shared.logger
    private let currentMessage: Message
    private var _currentRoute = ""
    private var _timeoutTimer: Timer?
    private var _elapsedTimer = ElapsedTimer()

    /// How long the engine gets to report `bootstrapped` before the message is treated as failed.
    static let bootstrapTimeoutSeconds: TimeInterval = 5.0

    public weak var delegate: EngineWebDelegate? {
        didSet {
            // `loadMessage()` runs from `init`, before the delegate exists, so a failure raised
            // there has nobody to report to yet. Deliver it as soon as one is attached.
            guard delegate != nil, let failure = pendingFailure else { return }
            pendingFailure = nil
            delegate?.error(failure)
        }
    }

    /// A failure raised before a delegate was attached, held until one is.
    private var pendingFailure: InAppMessageError?
    var webView = WKWebView()

    public var view: UIView {
        webView
    }

    private var currentConfiguration: EngineWebConfiguration
    private let colorSchemeMode: ColorScheme

    public private(set) var currentRoute: String {
        get { _currentRoute }
        set { _currentRoute = newValue }
    }

    /// Initializes the EngineWeb instance with the given configuration, state, and message.
    init(configuration: EngineWebConfiguration, state: InAppMessageState, message: Message) {
        self.currentMessage = message
        self.currentConfiguration = configuration
        self.colorSchemeMode = state.colorScheme

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
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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
            _timeoutTimer = Timer.scheduledTimer(timeInterval: Self.bootstrapTimeoutSeconds, target: self, selector: #selector(forcedTimeout), userInfo: nil, repeats: false)
            webView.load(URLRequest(url: url))
        } else {
            reportFailure(InAppMessageError(reason: .internalError, detail: "Invalid renderer URL: \(messageUrl)"))
        }
    }

    public func updateColorScheme(_ scheme: String) {
        applyInterfaceStyle(scheme)

        do {
            let jsonData = try JSONEncoder().encode(["action": "updateColorScheme", "colorScheme": scheme])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            let js = "window.postMessage(\(jsonString), '*');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        } catch {
            logger.logWithModuleTag("Failed to encode color scheme update: \(error)", level: .error)
        }
    }

    private func applyInterfaceStyle(_ scheme: String) {
        switch scheme {
        case "dark":
            webView.overrideUserInterfaceStyle = .dark
        case "light":
            webView.overrideUserInterfaceStyle = .light
        default:
            webView.overrideUserInterfaceStyle = .unspecified
        }
    }

    public func cleanEngineWeb() {
        _timeoutTimer?.invalidate()
        _timeoutTimer = nil
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "gist")
    }

    /// Single exit for every failure in this class: classify, log, then tell the delegate.
    ///
    /// `MessageManager` owns the resulting `messageLoadingFailed` dispatch — see `forcedTimeout`.
    /// A failure raised before the delegate is attached is held and delivered on assignment, so no
    /// path here reports into the void.
    private func reportFailure(_ error: InAppMessageError) {
        logger.logWithModuleTag(
            "Message \(currentMessage.describeForLogs) failed: \(error.describeForLogs)",
            level: .error
        )
        guard let delegate = delegate else {
            pendingFailure = error
            return
        }
        delegate.error(error)
    }

    @objc
    func forcedTimeout() {
        // Report through the delegate only. `MessageManager` turns this into a single
        // `messageLoadingFailed` dispatch, the same as every other failure site in this class.
        // Dispatching here as well delivered the host's error callback twice for a timeout.
        reportFailure(InAppMessageError(reason: .timeout, detail: "Engine did not bootstrap within \(Int(Self.bootstrapTimeoutSeconds))s"))
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
            reportFailure(InAppMessageError(
                reason: .renderFailed,
                detail: EngineEventHandler.getErrorProperties(properties: eventProperties)
            ))
        }
    }
}

// swiftlint:enable cyclomatic_complexity
extension EngineWeb: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let resolvedScheme = colorSchemeMode.resolve(with: webView.traitCollection)
        applyInterfaceStyle(resolvedScheme)
        currentConfiguration = EngineWebConfiguration(
            siteId: currentConfiguration.siteId,
            dataCenter: currentConfiguration.dataCenter,
            instanceId: currentConfiguration.instanceId,
            endpoint: currentConfiguration.endpoint,
            messageId: currentConfiguration.messageId,
            properties: currentConfiguration.properties,
            colorScheme: resolvedScheme
        )
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
                    self?.reportFailure(InAppMessageError(
                        reason: .internalError,
                        detail: "Configuration injection failed: \(error.localizedDescription)"
                    ))
                } else {
                    self?.logger.logWithModuleTag("Configuration injected successfully", level: .info)
                }
            }
        } catch {
            reportFailure(InAppMessageError(
                reason: .internalError,
                detail: "Failed to encode configuration: \(error.localizedDescription)"
            ))
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reportFailure(InAppMessageError(reason: .webViewCrashed, detail: "WebView content process terminated"))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportFailure(InAppMessageError(networkError: error))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportFailure(InAppMessageError(networkError: error))
    }
}
