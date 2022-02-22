import Foundation
#if canImport(UIKit)
import UIKit
import UserNotifications

public enum DeviceInfo {
    case deviceInfo
    case osInfo
    case customerAppName
    case customerAppVersion
    case customerBundleId
    case sdkVersion
    case deviceLocale
    
    public var value : String {
        switch self {
        case .deviceInfo:
            return UIDevice.deviceModelCode
        case .osInfo:
            return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        case .customerAppName:
            return Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
        case .customerAppVersion:
            return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        case .customerBundleId :
            return Bundle.main.bundleIdentifier ?? ""
        case .sdkVersion:
            return SdkVersion.version
        case .deviceLocale:
            return Locale.current.identifier
        }
    }
}

public class DeviceDetail {
    public init() {}
    
    public func pushSubscribed(completion: @escaping(Bool) -> Void) {
        let current = UNUserNotificationCenter.current()
        
        current.getNotificationSettings(completionHandler: { (settings) in
            if settings.authorizationStatus == .authorized {
                completion(true)
                return
            }
            completion(false)
        })
    }
}
#endif
