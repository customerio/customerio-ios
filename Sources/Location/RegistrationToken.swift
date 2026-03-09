import Foundation

/// A token that maintains a registration by its retention. When this token is deallocated,
/// the registration that generated it will be removed (the action runs once).
///
/// Call `remove()` to unregister explicitly, or release the token and the action runs in `deinit`.
/// The action is invoked at most once (either from `remove()` or `deinit`).
final class RegistrationToken<Identifier: Hashable & Sendable>: AppLifecycleObserverToken {
    let identifier: Identifier
    private var action: (() -> Void)?

    init(identifier: Identifier, action: @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    func remove() {
        action?()
        action = nil
    }

    deinit {
        action?()
        action = nil
    }
}
