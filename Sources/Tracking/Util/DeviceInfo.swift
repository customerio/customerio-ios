import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

public protocol DeviceInfo: AutoMockable {
    var deviceModel: String? { get }
    var osInfo: String? { get }
    var customerAppName: String { get }
    var customerAppVersion: String { get }
    var customerBundleId: String { get }
    var sdkVersion: String { get }
    var deviceLocale: String { get }
    func isPushSubscribed(completion: @escaping (Bool) -> Void)
}

// To get basic detail about the device SDK is working on
// such as operating system, customer app name, bundle id etc
// Class tested via QA testing.
//
// sourcery: InjectRegister = "DeviceInfo"
public class CIODeviceInfo: DeviceInfo {
    public var deviceModel: String? {
        #if canImport(UIKit)
        return UIDevice.deviceModelCode
        #else
        return nil
        #endif
    }

    public var osInfo: String? {
        #if canImport(UIKit)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        return nil
        #endif
    }

    public var customerAppName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    }

    public var customerAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    public var customerBundleId: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    public var sdkVersion: String {
        SdkVersion.version
    }

    public var deviceLocale: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    public func isPushSubscribed(completion: @escaping (Bool) -> Void) {
        #if canImport(UserNotifications)
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings(completionHandler: { settings in
            if settings.authorizationStatus == .authorized {
                completion(true)
                return
            }
            completion(false)
        })
        #else
        completion(false)
        #endif
    }
}
