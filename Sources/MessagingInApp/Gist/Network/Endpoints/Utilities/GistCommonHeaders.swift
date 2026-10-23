import CioInternalCommon
import Foundation

/// Headers every Gist request carries, so the queue fetch and the SSE connection describe
/// the client identically. Endpoint-specific headers stay with their call sites.
struct GistCommonHeaders {
    private let sdkClient: SdkClient
    private let deviceInfo: DeviceInfo

    init(sdkClient: SdkClient, deviceInfo: DeviceInfo) {
        self.sdkClient = sdkClient
        self.deviceInfo = deviceInfo
    }

    /// The public key identifies the workspace when the SDK has one, so the site ID is only sent without it.
    /// SSE passes `includeAuthorization: false`, as it sends the key in its URL instead.
    func headers(state: InAppMessageState, includeAuthorization: Bool = true) -> [String: String] {
        var headers = [
            HTTPHeader.cioDataCenter.rawValue: state.dataCenter,
            HTTPHeader.cioClientPlatform.rawValue: sdkClient.source.lowercased() + "-apple",
            HTTPHeader.cioClientVersion.rawValue: sdkClient.sdkVersion,
            HTTPHeader.cioClientAppIdentifier.rawValue: deviceInfo.customerBundleId
        ]
        if let publicKey = state.publicKey {
            if includeAuthorization {
                headers[HTTPHeader.authorization.rawValue] = "Bearer \(publicKey)"
            }
        } else {
            headers[HTTPHeader.siteId.rawValue] = state.siteId
        }
        return headers
    }
}
