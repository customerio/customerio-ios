import CioInternalCommon
import Foundation

extension InAppMessageState {
    /// Public key to send to gist alongside `siteId`. Uses the SDK's current key once it is set, since the
    /// key can be replaced, and sends none if that key isn't public. Falls back to the captured key until
    /// the SDK sets one, since in-app can start first.
    var requestPublicKey: String? {
        guard let currentKey = DIGraphShared.shared.backgroundDeliveryContextStore.currentCdpApiKey else {
            return publicKey
        }
        return ApiKey.isPublic(currentKey) ? currentKey : nil
    }
}
