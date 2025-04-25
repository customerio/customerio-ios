import Foundation

public protocol DeepLinkUtil: AutoMockable {
    @_spi(Internal) func setDeepLinkCallback(_ callback: @escaping DeepLinkCallback)
    func handleDeepLink(_ deepLinkUrl: URL)
}

public typealias DeepLinkCallback = (URL) -> Bool

@available(iOSApplicationExtension, unavailable)
// sourcery: InjectRegisterShared = "DeepLinkUtil"
// sourcery: InjectSingleton
public class DeepLinkUtilImpl: DeepLinkUtil {
    private let logger: Logger
    private let uiKit: UIKitWrapper
    private var deepLinkCallback: DeepLinkCallback?

    init(logger: Logger, uiKitWrapper: UIKitWrapper) {
        self.logger = logger
        self.uiKit = uiKitWrapper
    }

    @_spi(Internal) public func setDeepLinkCallback(_ callback: @escaping DeepLinkCallback) {
        deepLinkCallback = callback
    }

    public func handleDeepLink(_ deepLinkUrl: URL) {
        logger.info("Found a deep link inside of a push notification.")
        logger.debug("deep link found in push: \(deepLinkUrl)")

        /*
         There are 2 types of deep links:
         1. Universal Links which give URL format of a webpage using `http://` or `https://`
         2. App scheme which give URL format using a prototol other then `http://` or `https://`.

         We'll first provide URL to app to process them, which could be done in 2 ways:
         1. explicit `deepLinkCallback` first:
            - This is recommended option for client to use, as it will always work.
         3. UIKit's `application(_:continue:restorationHandler:)`
            - This is not recommended as it may fail for 3rd party SDK that are using swizzling.
            - Firebase has a known bug on this which is not solved for 3+ years (https://github.com/firebase/firebase-ios-sdk/issues/10417)

         If non of those 2 are available or return `false` (indicator that URL hasn't processed), we'll open URL through a sytem call.
         */
        var ifHandled = false
        if let deepLinkCallback {
            ifHandled = deepLinkCallback(deepLinkUrl)
        } else {
            ifHandled = uiKit.continueNSUserActivity(webpageURL: deepLinkUrl)
        }

        if !ifHandled {
            logger.debug("Opening deep link through system call. Deep link: \(deepLinkUrl)")
            uiKit.open(url: deepLinkUrl)
        } else {
            logger.debug("Handled by deep link callback. Deep link: \(deepLinkUrl)")
        }
    }
}
