import CioInternalCommon
import Foundation

/// Extension to access the Location module through CustomerIO.
public extension CustomerIO {
    /// Access the Location module.
    ///
    /// Use this to initialize and interact with location tracking.
    ///
    /// **Example:**
    /// ```swift
    /// CustomerIO.location().initialize(withConfig: LocationConfigBuilder().build())
    /// ```
    static func location() -> Location {
        Location.shared
    }
}
