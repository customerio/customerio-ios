import Foundation

protocol DeepLinksHandlerUtil {
    func handleAppSchemeDeepLink(_ url: URL) -> Bool
}

// sourcery: InjectRegister = "DeepLinksHandlerUtil"
class AppDeepLinksHandlerUtil: DeepLinksHandlerUtil {
    var storage = DI.shared.storage
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
    // Call this function if you have confirmed the deep link is a `deeplink` deep link. This function assumes you
    // have confirmed that.
    private func handleDeepLinkAction() -> Bool {
        if let email = storage.userEmailId, !email.isEmpty, let name = storage.userName, !name.isEmpty {
            NotificationCenter.default
                .post(
                    name: Notification.Name("showDeepLinkScreenOnDashboard"),
                    object: nil,
                    userInfo: nil
                )
        } else {
            NotificationCenter.default
                .post(
                    name: Notification.Name("showDeepLinkScreenOnLogin"),
                    object: nil,
                    userInfo: nil
                )
        }
        return true
    }
}
