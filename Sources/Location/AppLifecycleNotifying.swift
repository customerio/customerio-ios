import Foundation

/// Token returned when registering a lifecycle observer; pass to `removeObserver` to unregister.
protocol AppLifecycleObserverToken: AnyObject {}

/// Abstracts registration for app lifecycle notifications (didBecomeActive, didEnterBackground).
/// Enables tests to simulate lifecycle events without NotificationCenter or run loop.
protocol AppLifecycleNotifying: AnyObject {
    /// Registers for UIApplication.didBecomeActiveNotification. The block is invoked when the app becomes active.
    /// - Parameter block: Called when the notification fires (production: on main queue).
    /// - Returns: Token to pass to `removeObserver` when unregistering.
    @discardableResult
    func addDidBecomeActiveObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken

    /// Registers for UIApplication.didEnterBackgroundNotification. The block is invoked when the app enters background.
    /// - Parameter block: Called when the notification fires (production: on main queue).
    /// - Returns: Token to pass to `removeObserver` when unregistering.
    @discardableResult
    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken

    /// Unregisters a previously registered observer.
    func removeObserver(_ token: AppLifecycleObserverToken)
}
