@testable import CioLocation
import Foundation

/// No-op implementation of AppLifecycleNotifying for tests that don't need lifecycle behavior.
/// Registers nothing; callbacks are never invoked.
final class NoOpAppLifecycleNotifying: AppLifecycleNotifying {
    func addDidBecomeActiveObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        NoOpToken()
    }

    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        NoOpToken()
    }
}

private final class NoOpToken: AppLifecycleObserverToken {
    func remove() {}
}
