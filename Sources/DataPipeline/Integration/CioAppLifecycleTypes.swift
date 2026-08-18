/// The outcome of one scene lifecycle activation ingress.
public enum CioSceneLifecycleHandlingResult: Equatable, Sendable {
    /// The host routing closure accepted the activation.
    case handled

    /// The host routing closure declined the activation.
    case unhandled

    /// The callback contained no supported activation.
    case noActivation

    /// Notification response processing remains owned by `UNUserNotificationCenterDelegate`.
    case notificationOwnedByApplication

    /// More than one activation candidate was delivered for one callback.
    case rejectedAmbiguousInput

    /// Whether the host routing closure accepted the activation.
    public var wasHandled: Bool {
        self == .handled
    }
}
