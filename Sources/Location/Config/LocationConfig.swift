import Foundation

/// Configuration for the Customer.io Location module.
public struct LocationConfig: Sendable {
    /// Whether location tracking is enabled.
    ///
    /// When `false`, the Location module is effectively disabled and all location
    /// tracking operations will no-op silently.
    public let enableLocationTracking: Bool

    /// Creates a new LocationConfig.
    ///
    /// - Parameter enableLocationTracking: Whether location tracking is enabled.
    public init(enableLocationTracking: Bool) {
        self.enableLocationTracking = enableLocationTracking
    }
}
