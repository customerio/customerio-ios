import CioInternalCommon
import Foundation

extension InAppMessageState {
    /// Public key to send to gist. Prefers the SDK's current key, so a replaced `wk_` key takes over
    /// even when in-app captured an older one at startup. Falls back to the captured key. Without a
    /// captured key, only used when there's no `siteId`.
    var requestPublicKey: String? {
        guard publicKey != nil || siteId.isEmpty else {
            return nil
        }
        let currentKey = DIGraphShared.shared.backgroundDeliveryContextStore.currentCdpApiKey.flatMap { ApiKey.isPublic($0) ? $0 : nil }
        return currentKey ?? publicKey
    }
}
