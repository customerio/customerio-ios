import CioInternalCommon
import Foundation

public protocol DeepLinkDelegate: AnyObject, AutoMockable {
    func onOpenDeepLink(deepLink: DeepLink) -> Bool
}
