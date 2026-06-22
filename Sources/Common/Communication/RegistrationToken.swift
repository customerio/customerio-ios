import Foundation

/// A token that maintains a registration by its retention. When this token is deallocated,
/// the registration that generated it will be removed (the action runs once).
final class RegistrationToken<Identifier: Hashable & Sendable>: Sendable {
    let identifier: Identifier
    private let action: @Sendable () -> Void

    init(identifier: Identifier, action: @Sendable @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    deinit {
        action()
    }
}
