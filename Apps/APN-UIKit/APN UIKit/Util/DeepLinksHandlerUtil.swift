import Foundation

protocol DeepLinksHandlerUtil {
    func handleAppSchemeDeepLink(_ url: URL) -> Bool
    func handleUniversalLinkDeepLink(_ url: URL) -> Bool
}

// sourcery: InjectRegister = "DeepLinksHandlerUtil"
class AppDeepLinksHandlerUtil: DeepLinksHandlerUtil {
    var storage = DIGraph.shared.storage
    // URLs accepted:
    // apn-uikit://deeplink
    func handleAppSchemeDeepLink(_ url: URL) -> Bool {
        handleDeepLinkAction(url)
    }
}

extension AppDeepLinksHandlerUtil {
    // Call this function if you have confirmed the deep link is a `deeplink` deep link. This function assumes you
    // have confirmed that.
    private func handleDeepLinkAction(_ url: URL) -> Bool {
        if let host = url.host?.split(separator: "&"), host.first == "settings" {
            var userInfo: [String: String] = [String:String]()
            if host.count >= 3 {
                // Site ID
                let siteIdInfo = host[1].split(separator: "=")
                if siteIdInfo.first == "site_id" {
                    userInfo["site_id"] = String(siteIdInfo[1])
                }
                //API Key
                let apiKeyInfo = host[2].split(separator: "=")
                if apiKeyInfo.first == "api_key" {
                    userInfo["api_key"] = String(apiKeyInfo[1])
                }
            }
            if let _ = storage.userEmailId, let _ = storage.userName {
                NotificationCenter.default
                    .post(
                        name: Notification.Name("showSettingsScreenOnDashboard"),
                        object: nil,
                        userInfo: userInfo
                    )
                return true
            }
            NotificationCenter.default
                .post(
                    name: Notification.Name("showSettingsScreenOnLogin"),
                    object: nil,
                    userInfo: userInfo
                )
        }
        return true
    }

    func handleUniversalLinkDeepLink(_ url: URL) -> Bool {
        let userInfo = ["linkType": "Universal link", "link": url.path]
        if let _ = storage.userEmailId, let _ = storage.userName {
            NotificationCenter.default
                .post(
                    name: Notification.Name("showDeepLinkScreenOnDashboard"),
                    object: nil,
                    userInfo: userInfo
                )
        } else {
            NotificationCenter.default
                .post(
                    name: Notification.Name("showDeepLinkScreenOnLogin"),
                    object: nil,
                    userInfo: userInfo
                )
        }
        return true
    }
}
