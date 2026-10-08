import CioInternalCommon
import Foundation

extension InAppMessageState {
    /// Public key to send to gist alongside `siteId`. Prefers the SDK's current key, since in-app can
    /// start before the SDK sets it or the key can be replaced. Falls back to the captured key.
    var requestPublicKey: String? {
        let currentKey = DIGraphShared.shared.backgroundDeliveryContextStore.currentCdpApiKey.flatMap { ApiKey.isPublic($0) ? $0 : nil }
        return currentKey ?? publicKey
    }
}
