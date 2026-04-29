/// A tokent that maintains a registration by its retention. When this token is deallocated,
/// the registration that generated it will be removed.
public final class RegistrationToken<Identifier: Hashable & Sendable>: Sendable {
    public let identifier: Identifier
    private let action: @Sendable () -> Void

    public init(identifier: Identifier, action: @Sendable @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    deinit {
        action()
    }

}
