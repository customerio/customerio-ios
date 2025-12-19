import Foundation

public typealias SdkCommonLogger = Logger
public enum Tags {
    public static let Init = "Init"
    public static let Push = "Push"
}

extension SdkCommonLogger {

    public func coreSdkInitStart() {
        self.debug("Creating new instance of CustomerIO SDK version: \(SdkVersion.version)...", Tags.Init)
    }

    public func coreSdkInitSuccess() {
        info("CustomerIO SDK is initialized and ready to use", Tags.Init)
    }

    public func moduleInitStart(_ moduleName: String) {
        debug("Initializing SDK module \(moduleName)...", Tags.Init)
    }

    public func moduleInitSuccess(_ moduleName: String) {
        info("CustomerIO \(moduleName) module is initialized and ready to use", Tags.Init)
    }

    public func logHandlingNotificationDeepLink(url: URL) {
        debug("Handling push notification deep link with url: \(url)", Tags.Push)
    }

    public func logDeepLinkHandledByCallback() {
        debug("Deep link handled by host app callback implementation", Tags.Push)
    }

    public func logDeepLinkHandledByHostApp() {
        debug("Deep link handled by internal host app navigation", Tags.Push)
    }

    public func logDeepLinkHandledExternally() {
        debug("Deep link handled by system", Tags.Push)
    }

    public func logDeepLinkWasNotHandled() {
        debug("Deep link was not handled", Tags.Push)
    }
}
