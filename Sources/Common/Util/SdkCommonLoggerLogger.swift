import Foundation

public protocol SdkCommonLogger: AutoMockable {
    func coreSdkInitStart()
    func coreSdkInitSuccess()
    func moduleInitStart(_ moduleName: String)
    func moduleInitSuccess(_ moduleName: String)

    func logHandlingNotificationDeepLink(url: URL)
    func logDeepLinkHandledByCallback()
    func logDeepLinkHandledByHostApp()
    func logDeepLinkHandledExternally()
    func logDeepLinkWasNotHandled()
}

// sourcery: InjectRegisterShared = "SdkCommonLogger"
public class SdkCommonLoggerImpl: SdkCommonLogger {
    private static let INIT_TAG = "Init"
    private static let PUSH_TAG = "Push"

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    public func coreSdkInitStart() {
        logger.debug("Creating new instance of CustomerIO SDK version: \(SdkVersion.version)...", Self.INIT_TAG)
    }

    public func coreSdkInitSuccess() {
        logger.info("CustomerIO SDK is initialized and ready to use", Self.INIT_TAG)
    }

    public func moduleInitStart(_ moduleName: String) {
        logger.debug("Initializing SDK module \(moduleName)...", Self.INIT_TAG)
    }

    public func moduleInitSuccess(_ moduleName: String) {
        logger.info("CustomerIO \(moduleName) module is initialized and ready to use", Self.INIT_TAG)
    }

    public func logHandlingNotificationDeepLink(url: URL) {
        let tail = LogTail.make("push.deep_link", ["url": url.absoluteString])
        logger.debug("Handling push notification deep link with url: \(url)" + tail, Self.PUSH_TAG)
    }

    public func logDeepLinkHandledByCallback() {
        logger.debug("Deep link handled by host app callback implementation" + Self.outcomeTail("app_callback"), Self.PUSH_TAG)
    }

    public func logDeepLinkHandledByHostApp() {
        logger.debug("Deep link handled by internal host app navigation" + Self.outcomeTail("app_navigation"), Self.PUSH_TAG)
    }

    public func logDeepLinkHandledExternally() {
        logger.debug("Deep link handled by system" + Self.outcomeTail("system"), Self.PUSH_TAG)
    }

    public func logDeepLinkWasNotHandled() {
        logger.debug("Deep link was not handled" + Self.outcomeTail("not_handled"), Self.PUSH_TAG)
    }

    private static func outcomeTail(_ outcome: String) -> String {
        LogTail.make("push.deep_link_outcome", ["outcome": outcome])
    }
}
