import Foundation

public protocol UserAgentUtil: AutoMockable {
    func getUserAgentHeaderValue() -> String
    func getNSEUserAgentHeaderValue() -> String
}

// sourcery: InjectRegisterShared = "UserAgentUtil"
public class UserAgentUtilImpl: UserAgentUtil {
    private let deviceInfo: DeviceInfo
    private let mainTargetSdkClient: SdkClient
    private let nseSdkClient: SdkClient

    init(deviceInfo: DeviceInfo, sdkClient: SdkClient) {
        self.deviceInfo = deviceInfo
        self.mainTargetSdkClient = sdkClient
        self.nseSdkClient = DIGraphShared.shared.nseSdkClient
    }

    /**
     * getUserAgent - To get `user-agent` header value. This value depends on SDK version
     * and device detail such as OS version, device model, customer's app name etc
     *
     * In case, UIKit is available then this function returns value in following format :
     * `Customer.io iOS Client/1.0.0-alpha.16 (iPhone 11 Pro; iOS 14.5) User App/1.0`
     *
     * Otherwise will return
     * `Customer.io iOS Client/1.0.0-alpha.16`
     */
    public func getUserAgentHeaderValue() -> String {
        createUserAgentHeader(sdkClient: mainTargetSdkClient)
    }

    /**
     * Same as `getUserAgentHeaderValue` but this function returns value for NSE client
     */
    public func getNSEUserAgentHeaderValue() -> String {
        createUserAgentHeader(sdkClient: nseSdkClient)
    }

    /// Creates User-Agent header value based on given `SdkClient`
    private func createUserAgentHeader(sdkClient: SdkClient) -> String {
        var userAgent = "Customer.io \(sdkClient)"

        if let deviceModel = deviceInfo.deviceModel,
           let deviceOsVersion = deviceInfo.osVersion,
           let deviceOsName = deviceInfo.osName {
            userAgent += " (\(deviceModel); \(deviceOsName) \(deviceOsVersion))"
            userAgent += " \(deviceInfo.customerBundleId)/\(deviceInfo.customerAppVersion)"
        }

        return userAgent
    }
}
