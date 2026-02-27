import Foundation
import UIKit

/// Production implementation that registers for app lifecycle notifications via NotificationCenter.
/// Observers are invoked on the main queue.
final class RealAppLifecycleNotifying: AppLifecycleNotifying {
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func addDidBecomeActiveObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let token = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in block() }
        return Token(notificationCenter: notificationCenter, observer: token)
    }

    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let token = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in block() }
        return Token(notificationCenter: notificationCenter, observer: token)
    }

    func removeObserver(_ token: AppLifecycleObserverToken) {
        guard let token = token as? Token else { return }
        token.remove()
    }
}

// MARK: - Token

private final class Token: AppLifecycleObserverToken {
    private let notificationCenter: NotificationCenter
    private let observer: NSObjectProtocol

    init(notificationCenter: NotificationCenter, observer: NSObjectProtocol) {
        self.notificationCenter = notificationCenter
        self.observer = observer
    }

    func remove() {
        notificationCenter.removeObserver(observer)
    }
}
