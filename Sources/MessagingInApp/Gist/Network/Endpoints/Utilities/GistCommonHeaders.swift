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

    func headers(state: InAppMessageState) -> [String: String] {
        var headers = [
            HTTPHeader.cioDataCenter.rawValue: state.dataCenter,
            HTTPHeader.cioClientPlatform.rawValue: sdkClient.source.lowercased() + "-apple",
            HTTPHeader.cioClientVersion.rawValue: sdkClient.sdkVersion,
            HTTPHeader.cioClientAppIdentifier.rawValue: deviceInfo.customerBundleId
        ]
        // Site ID is optional when the SDK is set up with a public key.
        if !state.siteId.isEmpty {
            headers[HTTPHeader.siteId.rawValue] = state.siteId
        }
        if let publicKey = state.publicKey {
            headers[HTTPHeader.authorization.rawValue] = "Bearer \(publicKey)"
        }
        return headers
    }
}
