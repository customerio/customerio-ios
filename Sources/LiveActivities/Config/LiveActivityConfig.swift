import CioInternalCommon
import Foundation

/// Configuration for the Live Activities module.
///
/// Build instances via `LiveActivityConfigBuilder` and pass the result to
/// `LiveActivitiesModule.initialize(_:)`:
/// ```swift
/// CustomerIO.initialize(withConfig: config)
/// LiveActivitiesModule.initialize(
///     LiveActivityConfigBuilder()
///         .register(OrderAttributes.self, identifier: "io.customer.liveactivities.order")
///         .build()
/// )
/// ```
public struct LiveActivityConfig {
    /// Module-level log level override. When `nil`, the SDK-wide log level is used.
    public var logLevel: CioLogLevel?

    /// AppGroup container identifier used to share pre-loaded image assets with the
    /// widget extension. When `nil`, asset syncing is skipped.
    var appGroupIdentifier: String?

    /// Image assets declared for pre-loading into the AppGroup container at initialize time.
    var assetRegistrations: [AssetRegistration]

    /// Activity types registered for SDK observation via `LiveActivityConfigBuilder.register(_:identifier:)`.
    var registrations: [ActivityTypeRegistration]

    init(logLevel: CioLogLevel? = nil) {
        self.logLevel = logLevel
        self.appGroupIdentifier = nil
        self.assetRegistrations = []
        self.registrations = []
    }
}

/// A single image asset declared for pre-loading into the AppGroup container.
struct AssetRegistration: Sendable {
    let key: String
    let sourceURL: URL
}
