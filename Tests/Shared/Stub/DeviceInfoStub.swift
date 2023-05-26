@testable import CioInternalCommon
import Foundation

public class DeviceInfoStub: DeviceInfo {
    public var deviceManufacturer: String = "Apple"
    public var deviceModel: String? = "iPhone 14"
    public var osVersion: String? = "14"
    public var osName: String? = "iOS"
    public var customerAppName: String = "Super Awesome Store"
    public var customerAppVersion: String = "1.30.887"
    public var customerBundleId: String = "io.customer.superawesomestore"
    public var sdkVersion: String = "2.0.3"
    public var deviceLocale: String = "en-US"

    public func isPushSubscribed(completion: @escaping (Bool) -> Void) {
        completion(false)
    }
}
