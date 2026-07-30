import CioInternalCommon
import Foundation

/// Configuration for the Live Activities module.
///
/// Build instances via `LiveActivityConfigBuilder` and pass the result to
/// `LiveActivitiesModule(config:)`, then register it before `CustomerIO.initialize(withConfig:)`:
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LiveActivitiesModule(config:
///         LiveActivityConfigBuilder()
///             .register(OrderAttributes.self, identifier: "io.customer.livenotifications.order")
///             .build()))
///     .build()
/// CustomerIO.initialize(withConfig: config)
/// ```
public struct LiveActivityConfig {
    /// Module-level log level override. When `nil`, the SDK-wide log level is used.
    public var logLevel: CioLogLevel?

    /// Activity types registered for SDK observation via `LiveActivityConfigBuilder.register(_:identifier:)`.
    var registrations: [ActivityTypeRegistration]

    init(logLevel: CioLogLevel? = nil) {
        self.logLevel = logLevel
        self.registrations = []
    }
}
