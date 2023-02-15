import Common
import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol DeepLinkUtil: AutoMockable {
    func handleDeepLink(_ deepLinkUrl: URL)
}

// sourcery: InjectRegister = "DeepLinkUtil"
class DeepLinkUtilImpl: DeepLinkUtil {
    private let logger: Logger
    private let uiKit: UIKitWrapper

    init(logger: Logger, uiKitWrapper: UIKitWrapper) {
        self.logger = logger
        self.uiKit = uiKitWrapper
    }

    func handleDeepLink(_ deepLinkUrl: URL) {
        logger.debug("Found a deep link inside of a push notification \(deepLinkUrl)")

        // First, try to open the link inside of the host app. This is to keep compatability with Universal Links.
        // Learn more of edge case: https://github.com/customerio/customerio-ios/issues/262
        // Fallback to opening the URL system-wide if fail to open link in host app.
        // Customers with Universal Links in their app will need to add this function to their `AppDelegate` which will get called with deep link:
        // func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool
        let ifHandled = uiKit.continueNSUserActivity(webpageURL: deepLinkUrl)

        if !ifHandled {
            logger.debug("Opening deep link through system call.")
            uiKit.open(url: deepLinkUrl)
        }
    }
}
