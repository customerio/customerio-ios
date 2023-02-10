import Common
import Foundation

protocol DeepLinkUtil: AutoMockable {
    func isLinkValidNSUserActivityLink(_ url: URL) -> Bool
}

// sourcery: InjectRegister = "DeepLinkUtil"
class DeepLinkUtilImpl: DeepLinkUtil {
    // When using `NSUserActivity.webpageURL`, only certain URL schemes are allowed. An exception will be thrown otherwise which is why we have this function.
    func isLinkValidNSUserActivityLink(_ url: URL) -> Bool {
        guard let schemeOfUrl = url.scheme else {
            return false
        }

        // All allowed schemes in docs: https://developer.apple.com/documentation/foundation/nsuseractivity/1418086-webpageurl
        let allowedSchemes = ["http", "https"]

        return allowedSchemes.contains(schemeOfUrl)
    }
}
