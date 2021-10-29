import Foundation
import UIKit

internal enum DeviceInfo {
    static let deviceInfo: String = UIDevice.deviceModelCode
    static let phoneName : String = Bundle.main.infoDictionary?["CFBundleName"] as! String
    static let osInfo : String = "\(UIDevice().systemName) \(UIDevice().systemVersion)"
    static let customerAppName : String = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    static let customerAppVersion : String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
}
