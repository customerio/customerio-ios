import Foundation

/// Mode for location tracking behavior.
///
/// - **off**: Location tracking is disabled. All location APIs no-op silently.
/// - **manual**: The host app must call `requestLocationUpdate()` and/or `setLastKnownLocation(_:)` when it wants to send location; the SDK does not request location automatically.
/// - **onAppStart**: The SDK automatically requests location once per app launch when the app becomes active (subject to permissions). The host app may still call the APIs at any time.
public enum LocationTrackingMode: Sendable {
    /// Location tracking is disabled. All location operations no-op.
    case off
    /// Only manual updates; customer must call `requestLocationUpdate()` or `setLastKnownLocation(_:)`. No automatic requests.
    case manual
    /// SDK requests location once per app launch when the app becomes active (when permission is granted).
    case onAppStart
}

/// Configuration for the Customer.io Location module.
public struct LocationConfig: Sendable {
    /// How location tracking is used.
    ///
    /// Use `.off` to disable location, `.manual` when your app will call the location APIs itself,
    /// or `.onAppStart` to have the SDK request location once per app launch when the app becomes active.
    public let mode: LocationTrackingMode

    /// Creates a new LocationConfig.
    ///
    /// - Parameter mode: The location tracking mode (off, manual, or onAppStart). With `.onAppStart`, the SDK requests location once per app launch when permission is granted.
    public init(mode: LocationTrackingMode) {
        self.mode = mode
    }
}
