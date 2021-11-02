import Foundation
#if canImport(UIKit)
import UIKit

internal enum DeviceInfo {
    /// Device's model on which SDK is running eg. iPhone12,3
    static let deviceInfo: String = UIDevice.deviceModelCode
    /// Operating system and version of OS of the Device
    static let osInfo : String = "\(UIDevice().systemName) \(UIDevice().systemVersion)"
    /// Name of customer's application using the SDK
    static let customerAppName : String = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    /// Version of the customer's application using the SDK
    static let customerAppVersion : String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
}
#endif
