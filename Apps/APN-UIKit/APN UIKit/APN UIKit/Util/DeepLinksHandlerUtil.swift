import Foundation

protocol DeepLinksHandlerUtil {
    func handleAppSchemeDeepLink(_ url: URL) -> Bool
}

// sourcery: InjectRegister = "DeepLinksHandlerUtil"
class AppDeepLinksHandlerUtil: DeepLinksHandlerUtil {
    

    // URLs accepted:
    // apn-uikit://deeplink
    func handleAppSchemeDeepLink(_ url: URL) -> Bool {
        switch url.host {
        case "deeplink":
            return handleDeepLinkAction()
        default: return false
        }
    }
}

extension AppDeepLinksHandlerUtil {
    // Call this function if you have confirmed the deep link is a switch_workspace deep link. This function assumes you
    // have confirmed that.
    private func handleDeepLinkAction() -> Bool {
        NotificationCenter.default
            .post(name: Notification.Name("showDeepLinkScreen"),
                  object: nil, userInfo: nil)

        return true
    }
}
