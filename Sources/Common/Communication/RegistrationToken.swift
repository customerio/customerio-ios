import Foundation

/// An opaque token issued when an observer is registered on the event bus.
/// Held by the caller to enable future per-observer removal without clearing
/// all observers for the same event type.
public struct RegistrationToken: Hashable, Sendable {
    let id: UUID

    public init() {
        id = UUID()
    }
}
