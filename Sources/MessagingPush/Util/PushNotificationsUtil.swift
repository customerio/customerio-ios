import Common
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum PushPermissionStatus {
    case authorized
    case denied
    case notDetermined
    case provisional
    case ephemeral
    case unknown
}

protocol PushNotificationsUtil: AutoMockable {
    func showPromptForPushNotificationPermission(options:[String: Any], onComplete: @escaping (Result<Bool, Error>) -> Void)
}

// sourcery: InjectRegister = "PushNotificationsUtil"
class PushNotificationsImpl: PushNotificationsUtil {
    private let logger: Logger
    private let uiKit: UIKitWrapper

    init(logger: Logger, uiKitWrapper: UIKitWrapper) {
        self.logger = logger
        self.uiKit = uiKitWrapper
    }

    func showPromptForPushNotificationPermission(options:[String: Any], onComplete: @escaping (Result<Bool, Error>) -> Void) {
        // Show prompt if status is not determined
        getPushNotificationPermissionStatus { status in
            if status == .notDetermined {
                let current = UNUserNotificationCenter.current()
                var notificationOptions : UNAuthorizationOptions = [.alert]
                if let ios = options["ios"] as? [String: Any], let sound = ios["sound"] as? Bool, let bagdeOption = ios["badge"] as? Bool {
                    
                    if sound {
                        notificationOptions.insert(.sound)
                    }
                    if bagdeOption {
                        notificationOptions.insert(.badge)
                    }
                }
                current.requestAuthorization(options: notificationOptions) { isGranted, error in
                    if let error = error {
                        onComplete(.failure(error))
                        return
                    }
                   onComplete(.success(isGranted))
                }
            }
        }
    }
    
    private func getPushNotificationPermissionStatus(completionHandler: @escaping(PushPermissionStatus) -> Void) {
        var status = PushPermissionStatus.unknown
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings(completionHandler: { permission in
            switch permission.authorizationStatus  {
            case .authorized:
                status = .authorized
            case .denied:
                status = .denied
            case .notDetermined:
                status = .notDetermined
            case .ephemeral: // authorized to send or receive notifications for limited time
                // @available(iOS 14.0, *)
                status = .ephemeral
            case .provisional: //authoized to push non-interuptive notifications
                // @available(iOS 12.0, *)
                status = .provisional
            default:
                status = .unknown
            }
            completionHandler(status)
        })
    }
}
