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
        if let urlComponents = URLComponents(string: url.absoluteString), let host = urlComponents.host, host == "settings" {
            var userInfo: [String: String] = [:]

            urlComponents.queryItems?.forEach { queryItem in
                if queryItem.name == "site_id" || queryItem.name == "api_key" {
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
        }
        return true
    }

    func handleUniversalLinkDeepLink(_ url: URL) -> Bool {
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
        // navigation to browser depends if we handle the url inside app or not
        return doesMatchUniversalLink(url)
    }

    /// Check if a provided URL matches a predefined universal link that app supports..
    /// - Parameter url: The URL to be checked.
    /// - Returns: A boolean indicating whether the provided URL matches the universal link.
    func doesMatchUniversalLink(_ url: URL) -> Bool {
        let universalLink = URL(string: "http://applinks:ciosample.page.link/spm")

        return (url.scheme == "http" || url.scheme == "https") &&
            url.host == universalLink?.host &&
            url.path == universalLink?.path
    }
}
