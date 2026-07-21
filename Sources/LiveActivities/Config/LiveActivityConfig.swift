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
///         .register(OrderAttributes.self, identifier: "io.customer.livenotifications.order")
///         .build()
/// )
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
