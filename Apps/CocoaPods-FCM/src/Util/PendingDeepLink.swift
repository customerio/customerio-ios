import CioTracking
import Combine
import Foundation

class PendingDeepLink: ObservableObject {
    public static let shared = PendingDeepLink() // make this a singleton to store the pending deep link

    @Published var pendingDeepLink: DeepLink?
    @Published var pendingDeepLinkAvailable: Bool = false

    private init() {}

    func getAndResetDeepLink() -> DeepLink? {
        guard let deepLink = pendingDeepLink else {
            return nil
        }

        pendingDeepLinkAvailable = false
        pendingDeepLink = nil

        return deepLink
    }
}

extension PendingDeepLink: DeepLinkDelegate {
    func onOpenDeepLink(deepLink: DeepLink) -> Bool {
        pendingDeepLink = deepLink
        pendingDeepLinkAvailable = true

        return true
    }
}
