/// The host lifecycle surface that owns UI activation callbacks for one coordinator.
///
/// Choose this explicitly from the host's architecture. The coordinator never infers topology
/// from missing callbacks, OS version, or the presence of a scene manifest.
public enum CioAppLifecycleHostTopology: String, Sendable {
    /// UIKit routes activations through `UIApplicationDelegate` callbacks.
    case appDelegateOnly = "app-delegate-only"

    /// UIKit routes activations through `UISceneDelegate` callbacks.
    case uiScene = "ui-scene"

    /// SwiftUI routes UI activations through view lifecycle callbacks such as `onOpenURL`.
    /// A `UIApplicationDelegateAdaptor` may still own application-global initialization, token,
    /// and notification callbacks, but it must not route the same UI activation through this
    /// coordinator's AppDelegate-only methods.
    case swiftUILifecycle = "swiftui-lifecycle"
}

/// The outcome of handling one lifecycle activation ingress.
public enum CioAppLifecycleHandlingResult: Equatable, Sendable {
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

    /// A callback from a lifecycle surface other than the configured host topology was rejected.
    case rejectedHostTopology

    /// Whether the host routing closure accepted the activation.
    public var wasHandled: Bool {
        self == .handled
    }
}
