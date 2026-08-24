import Foundation

protocol DeepLinksHandlerUtil {
    func handleAppSchemeDeepLink(_ url: URL) -> Bool
    func handleUniversalLinkDeepLink(_ url: URL) -> Bool
}

// sourcery: InjectRegisterShared = "DeepLinksHandlerUtil"
class AppDeepLinksHandlerUtil: DeepLinksHandlerUtil {
    var storage = DIGraphShared.shared.storage
    // URLs accepted:
    // apn-uikit://deeplink
    func handleAppSchemeDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "apn-uikit" else { return false }
        return handleDeepLinkAction(url)
    }
}

extension AppDeepLinksHandlerUtil {
    // Call this function if you have confirmed the deep link is a `deeplink` deep link. This function assumes you
    // have confirmed that.
    private func handleDeepLinkAction(_ url: URL) -> Bool {
        guard let urlComponents = URLComponents(string: url.absoluteString),
              urlComponents.host == "settings" else { return false }

        var userInfo: [String: String] = [:]

        urlComponents.queryItems?.forEach { queryItem in
            if queryItem.name == "site_id" || queryItem.name == "cdp_api_key" {
                userInfo[queryItem.name] = queryItem.value
            }
        }

        if let _ = storage.userEmailId {
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
        return true
    }

    func handleUniversalLinkDeepLink(_ url: URL) -> Bool {
        guard doesMatchUniversalLink(url) else { return false }

        let userInfo = ["linkType": "Universal link", "link": url.path]
        if let _ = storage.userEmailId {
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

    /// Check if a provided URL matches a predefined universal link that app supports..
    /// - Parameter url: The URL to be checked.
    /// - Returns: A boolean indicating whether the provided URL matches the universal link.
    func doesMatchUniversalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }

        return (scheme == "http" || scheme == "https") &&
            host == "ciosample.page.link" &&
            url.path == "/spm"
    }
}
