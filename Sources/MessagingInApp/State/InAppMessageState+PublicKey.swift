import CioInternalCommon
import Foundation

extension InAppMessageState {
    /// Public key to send to gist. In-app can start before the SDK sets its key, so without a
    /// `siteId` this falls back to the SDK's current key at request time.
    var requestPublicKey: String? {
        if let publicKey {
            return publicKey
        }
        guard siteId.isEmpty else {
            return nil
        }
        return DIGraphShared.shared.backgroundDeliveryContextStore.currentCdpApiKey.flatMap { ApiKey.isPublic($0) ? $0 : nil }
    }
}
