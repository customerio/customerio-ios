import Foundation

/// Token returned when registering a lifecycle observer. Retain the token; call `remove()` to unregister, or let it deallocate and the registration is removed automatically.
protocol AppLifecycleObserverToken: AnyObject {
    /// Unregisters the observer. Safe to call multiple times; only the first call has effect.
    func remove()
}

/// Abstracts registration for app lifecycle notifications (didBecomeActive, didEnterBackground).
/// Enables tests to simulate lifecycle events without NotificationCenter or run loop.
protocol AppLifecycleNotifying: AnyObject {
    /// Registers for UIApplication.didBecomeActiveNotification. The block is invoked when the app becomes active.
    /// - Parameter block: Called when the notification fires (production: on main queue).
    /// - Returns: Token to retain; call `remove()` to unregister or release the token to unregister on dealloc.
    func addDidBecomeActiveObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken

    /// Registers for UIApplication.didEnterBackgroundNotification. The block is invoked when the app enters background.
    /// - Parameter block: Called when the notification fires (production: on main queue).
    /// - Returns: Token to retain; call `remove()` to unregister or release the token to unregister on dealloc.
    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken
}
