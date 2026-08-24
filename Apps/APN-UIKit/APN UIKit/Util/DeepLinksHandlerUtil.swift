import Foundation

protocol DeepLinksHandlerUtil {
    /// Routes an app-scheme URL owned by the sample app.
    func handleAppSchemeDeepLink(_ url: URL) -> Bool

    /// Routes a universal link owned by the sample app.
    func handleUniversalLinkDeepLink(_ url: URL) -> Bool
}

// sourcery: InjectRegisterShared = "DeepLinksHandlerUtil"
class AppDeepLinksHandlerUtil: DeepLinksHandlerUtil {
    private let storage: StorageManager
    private let notificationCenter: NotificationCenter

    init(
        storage: StorageManager = DIGraphShared.shared.storage,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage
        self.notificationCenter = notificationCenter
    }

    // Handles the sample app's `apn-uikit://settings` route. Other app-scheme URLs fall through
    // so UIScene or the system can route them.
    func handleAppSchemeDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "apn-uikit" else { return false }
        return handleDeepLinkAction(url)
    }
}

extension AppDeepLinksHandlerUtil {
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
            post(name: "showSettingsScreenOnDashboard", userInfo: userInfo)
            return true
        }
        post(name: "showSettingsScreenOnLogin", userInfo: userInfo)
        return true
    }

    func handleUniversalLinkDeepLink(_ url: URL) -> Bool {
        guard doesMatchUniversalLink(url) else { return false }

        let userInfo = ["linkType": "Universal link", "link": url.path]
        if let _ = storage.userEmailId {
            post(name: "showDeepLinkScreenOnDashboard", userInfo: userInfo)
        } else {
            post(name: "showDeepLinkScreenOnLogin", userInfo: userInfo)
        }
        return true
    }

    private func post(name: String, userInfo: [String: String]) {
        let notificationCenter = notificationCenter
        DispatchQueue.main.async {
            notificationCenter.post(
                name: Notification.Name(name),
                object: nil,
                userInfo: userInfo
            )
        }
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
