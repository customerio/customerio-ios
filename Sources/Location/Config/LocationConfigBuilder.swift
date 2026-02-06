import Foundation

/// Builder for creating `LocationConfigOptions`.
///
/// Uses value semantics for thread safety and `Sendable` conformance.
///
/// **Usage Example:**
/// ```swift
/// let config = LocationConfigBuilder()
///     .build()
/// ```
public struct LocationConfigBuilder: Sendable {
    public init() {}

    /// Builds and returns `LocationConfigOptions` instance from the configured properties.
    public func build() -> LocationConfigOptions {
        LocationConfigOptions()
    }
}
