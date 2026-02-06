import Foundation

/// Class managing the Location module singleton.
public final class Location: Sendable {
    /// Shared instance of the Location module.
    public static let shared = Location()

    private init() {}

    /// Initialize the Location module.
    ///
    /// Call this function after initializing the Customer.io SDK.
    ///
    /// - Parameter config: Configuration options for the Location module.
    @discardableResult
    public func initialize(withConfig config: LocationConfigOptions) -> Location {
        // Implementation will be added in future milestones
        self
    }
}
