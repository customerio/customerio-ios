import Foundation

protocol DeepLinksHandlerUtil {
    func handleAppSchemeDeepLink(_ url: URL) -> Bool
    func handleUniversalLinkDeepLink(_ url: URL) -> Bool
}

// sourcery: InjectRegister = "DeepLinksHandlerUtil"
class AppDeepLinksHandlerUtil: DeepLinksHandlerUtil {
    

    var storage = DI.shared.storage
    // URLs accepted:
    // apn-uikit://deeplink
    func handleAppSchemeDeepLink(_ url: URL) -> Bool {
        return handleDeepLinkAction(url)
    }
}

extension AppDeepLinksHandlerUtil {
    // Call this function if you have confirmed the deep link is a `deeplink` deep link. This function assumes you
    // have confirmed that.
    private func handleDeepLinkAction(_ url: URL) -> Bool {
        
        let userInfo = ["linkType" : "Deep link", "link" : url.host ?? ""]
        if let _ = storage.userEmailId, let _ = storage.userName {
            NotificationCenter.default
                .post(name: Notification.Name("showDeepLinkScreenOnDashboard"),
                      object: nil, userInfo: userInfo)
        }
        else {
            NotificationCenter.default
                .post(name: Notification.Name("showDeepLinkScreenOnLogin"),
                      object: nil, userInfo: userInfo)
        }
        return true
    }
    
    func handleUniversalLinkDeepLink(_ url: URL) -> Bool {
        let userInfo = ["linkType" : "Universal link", "link" : url.path]
        if let _ = storage.userEmailId, let _ = storage.userName {
            NotificationCenter.default
                .post(name: Notification.Name("showDeepLinkScreenOnDashboard"),
                      object: nil, userInfo: userInfo)
        }
        else {
            NotificationCenter.default
                .post(name: Notification.Name("showDeepLinkScreenOnLogin"),
                      object: nil, userInfo: userInfo)
        }
        return true
    }
}
