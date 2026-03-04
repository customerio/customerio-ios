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
        let id = nextId
        nextId += 1
        let token = StubToken(id: id) { [weak self] in
            self?.removeRegistration(byId: id)
        }
        becomeActiveRegistrations.append(Registration(token: token, block: block))
        return token
    }

    func addDidEnterBackgroundObserver(using block: @escaping () -> Void) -> AppLifecycleObserverToken {
        let id = nextId
        nextId += 1
        let token = StubToken(id: id) { [weak self] in
            self?.removeRegistration(byId: id)
        }
        enterBackgroundRegistrations.append(Registration(token: token, block: block))
        return token
    }

    private func removeRegistration(byId id: Int) {
        becomeActiveRegistrations.removeAll { $0.token.id == id }
        enterBackgroundRegistrations.removeAll { $0.token.id == id }
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
    private var onRemove: (() -> Void)?

    init(id: Int, onRemove: @escaping () -> Void) {
        self.id = id
        self.onRemove = onRemove
    }

    func remove() {
        onRemove?()
        onRemove = nil
    }
}
