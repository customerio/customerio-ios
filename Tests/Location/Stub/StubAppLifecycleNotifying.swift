@testable import CioLocation
import Foundation

/// Stub implementation of AppLifecycleNotifying for tests. Holds registered blocks and exposes
/// simulateDidBecomeActive() / simulateDidEnterBackground() to invoke them synchronously (no NotificationCenter, no sleep).
final class StubAppLifecycleNotifying: AppLifecycleNotifying {
    struct Registration {
        fileprivate let token: StubToken
        let block: () -> Void
    }

    fileprivate var becomeActiveRegistrations: [Registration] = []
    fileprivate var enterBackgroundRegistrations: [Registration] = []
    private var nextId = 0

    func addDidBecomeActiveObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let token = StubToken(id: nextId)
        nextId += 1
        becomeActiveRegistrations.append(Registration(token: token, block: block))
        return token
    }

    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let token = StubToken(id: nextId)
        nextId += 1
        enterBackgroundRegistrations.append(Registration(token: token, block: block))
        return token
    }

    func removeObserver(_ token: AppLifecycleObserverToken) {
        guard let stubToken = token as? StubToken else { return }
        becomeActiveRegistrations.removeAll { $0.token.id == stubToken.id }
        enterBackgroundRegistrations.removeAll { $0.token.id == stubToken.id }
    }

    /// Invokes all registered didBecomeActive blocks synchronously.
    func simulateDidBecomeActive() {
        for reg in becomeActiveRegistrations {
            reg.block()
        }
    }

    /// Invokes all registered didEnterBackground blocks synchronously.
    func simulateDidEnterBackground() {
        for reg in enterBackgroundRegistrations {
            reg.block()
        }
    }
}

private final class StubToken: AppLifecycleObserverToken {
    let id: Int
    init(id: Int) { self.id = id }
}
