import Foundation
#if canImport(UIKit) && canImport(UserNotifications)
import UIKit
import UserNotifications

/// To get basic detail about the device SDK is working on
/// such as operating system, customer app name, bundle id etc

public class DeviceInfo {
    public init() {}
    public var deviceInfo: String {
        return UIDevice.deviceModelCode
    }
    public var osInfo: String {
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
    public var customerAppName: String {
        return Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    }
    public var customerAppVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    public var customerBundleId: String {
        return Bundle.main.bundleIdentifier ?? ""
    }
    public var sdkVersion: String {
        return SdkVersion.version
    }
    public var deviceLocale: String {
        return Locale.current.identifier
    }
    public func pushSubscribed(completion: @escaping(Bool) -> Void) {
        if let executableBundle = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String,
           executableBundle == "xctest" {
            completion(false)
            return
        }
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
