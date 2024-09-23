@testable import CioInternalCommon
import Foundation

public class DeviceInfoStub: DeviceInfo {
    private let sdkClient: SdkClient

    init(sdkClient: SdkClient) {
        self.sdkClient = sdkClient
    }

    public var deviceManufacturer: String = "Apple"
    public var deviceModel: String? = "iPhone 14"
    public var osVersion: String? = "14"
    public var osName: String? = "iOS"
    public var customerAppName: String = "Super Awesome Store"
    public var customerAppVersion: String = "1.30.887"
    public var customerBundleId: String = "io.customer.superawesomestore"
    public var deviceLocale: String = "en-US"

    public func isPushSubscribed(completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func getDefaultAttributes(isPushSubscribed: Bool = false) -> [String: Any] {
        var attributes: [String: Any] = [:]
        attributes["cio_sdk_version"] = sdkClient.sdkVersion
        attributes["app_version"] = customerAppVersion
        attributes["device_locale"] = deviceLocale
        attributes["device_manufacturer"] = deviceManufacturer
        attributes["device_model"] = deviceModel
        attributes["device_os"] = osVersion
        attributes["push_enabled"] = String(isPushSubscribed)
        return attributes
    }
}

extension DeviceInfoStub {
    /// Since cio_sdk_version relies on SdkClient, we need to create and override SdkClient every
    /// time we create DeviceInfoStub in tests to make sure the version matches the expected values.
    /// The method allows to create and override SdkClient and DeviceInfoStub in one go to simplify
    /// using stub in tests.
    /// This isn't the best approach, but it's the best we can do without changing the design of tests
    /// at this point. We can refactor this in the future to decouple these two classes further.
    static func createAndOverride(for diGraph: DIManager) -> DeviceInfoStub {
        let sdkClientMock = SdkClientMock()
        sdkClientMock.underlyingSource = "iOS"
        sdkClientMock.underlyingSdkVersion = "2.0.3"
        diGraph.override(value: sdkClientMock, forType: SdkClient.self)

        let deviceInfoStub = DeviceInfoStub(sdkClient: sdkClientMock)
        diGraph.override(value: deviceInfoStub, forType: DeviceInfo.self)

        return deviceInfoStub
    }
}
