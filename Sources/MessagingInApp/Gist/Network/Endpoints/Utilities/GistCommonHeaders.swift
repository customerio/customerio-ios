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
        [
            HTTPHeader.siteId.rawValue: state.siteId,
            HTTPHeader.cioDataCenter.rawValue: state.dataCenter,
            HTTPHeader.cioClientPlatform.rawValue: sdkClient.source.lowercased() + "-apple",
            HTTPHeader.cioClientVersion.rawValue: sdkClient.sdkVersion,
            HTTPHeader.cioClientAppIdentifier.rawValue: deviceInfo.customerBundleId
        ]
    }
}
