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
    public var deviceLocale: String = "en-US"

    public func isPushSubscribed(completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func getDefaultAttributes(isPushSubscribed: Bool = false) -> [String: Any] {
        var attributes: [String: Any] = [:]
        attributes["app_version"] = customerAppVersion
        attributes["device_locale"] = deviceLocale
        attributes["device_manufacturer"] = deviceManufacturer
        attributes["device_model"] = deviceModel
        attributes["device_os"] = osVersion
        attributes["push_enabled"] = String(isPushSubscribed)
        return attributes
    }
}
