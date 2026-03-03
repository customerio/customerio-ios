import Foundation
import UIKit

/// Production implementation that registers for app lifecycle notifications via NotificationCenter.
/// Observers are invoked on the main queue.
/// Uses `RegistrationToken` so that when the token is released, the observer is automatically removed.
final class RealAppLifecycleNotifying: AppLifecycleNotifying {
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func addDidBecomeActiveObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let observer = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in block() }
        return RegistrationToken(identifier: UUID(), action: { [notificationCenter] in
            notificationCenter.removeObserver(observer)
        })
    }

    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let observer = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in block() }
        return RegistrationToken(identifier: UUID(), action: { [notificationCenter] in
            notificationCenter.removeObserver(observer)
        })
    }
}
