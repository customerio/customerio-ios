import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit

/// The SDK navigation the inbox performs for an un-intercepted, non-dismiss action. Abstracted behind
/// a protocol so ``NotificationInboxView`` can be exercised — including its navigate/dismiss ordering
/// and host-interception paths — without `DIGraphShared` or live UIKit, keeping the shared graph at
/// the module boundary with constructor injection below it (per the SDK DI guidelines).
protocol InboxActionNavigating {
    /// Open an external URL (web parity `openUrl`) — the system browser or whichever app claims it.
    func openExternalURL(_ url: URL)
    /// Route a deep link through the SDK's shared handling (host `deepLinkCallback` → universal-link
    /// handoff → system open), identical to push-notification and in-app-message deep links.
    func handleDeepLink(_ url: URL)
}

/// Production ``InboxActionNavigating`` backed by the SDK's shared `DeepLinkUtil` and `UIApplication`.
struct DefaultInboxActionNavigator: InboxActionNavigating {
    private let deepLinkUtil: DeepLinkUtil

    /// - Parameter deepLinkUtil: defaults to the shared graph's util, resolved at this call boundary;
    ///   inject a fake below the boundary (e.g. in tests).
    init(deepLinkUtil: DeepLinkUtil = DIGraphShared.shared.deepLinkUtil) {
        self.deepLinkUtil = deepLinkUtil
    }

    func openExternalURL(_ url: URL) {
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    func handleDeepLink(_ url: URL) {
        let deepLinkUtil = deepLinkUtil
        DispatchQueue.main.async { deepLinkUtil.handleDeepLink(url) }
    }
}
#endif
