import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit
#endif

/// Fluent builder for `LiveActivityConfig`.
///
/// ```swift
/// LiveActivityConfigBuilder()
///     .logLevel(.debug)
///     .register(OrderAttributes.self, identifier: "io.customer.liveactivities.order")
///     .build()
/// ```
public struct LiveActivityConfigBuilder {
    private var config: LiveActivityConfig

    public init() {
        self.config = LiveActivityConfig()
    }

    // MARK: - Fluent configuration

    /// Override the SDK-wide log level for the Live Activities module only.
    public func logLevel(_ level: CioLogLevel) -> Self {
        var copy = self
        copy.config.logLevel = level
        return copy
    }

    /// Register an `ActivityAttributes` type for SDK observation.
    ///
    /// The SDK monitors all live activities whose attributes type is `T`, forwarding
    /// push-to-start and per-instance push tokens to the Customer.io backend, and enables the
    /// local `start`/`update`/`end` API for this type. Call once per distinct type.
    ///
    /// - Parameters:
    ///   - type: The `ActivityAttributes` conformance to observe.
    ///   - identifier: A stable reverse-DNS identifier for this activity type,
    ///     e.g. `"io.customer.liveactivities.scoreboard"`. Sent as `notificationType` and matched
    ///     server-side to route pushes. Must be consistent between the app and the backend.
    ///
    /// Conform `T` to `CIOActivityAttribute` (adding a `cioInstanceId` field) to also enable
    /// **push-to-start**. A plain `ActivityAttributes` type is fully supported for local
    /// `start`/`adopt`, instance-token push updates, and relaunch recovery — everything except
    /// push-to-start. The correct behavior is selected automatically by which overload applies.
    #if os(iOS)
    @available(iOS 16.2, *)
    public func register<T: CIOActivityAttribute>(_ type: T.Type, identifier: String) -> Self {
        var copy = self
        copy.config.registrations.append(
            LiveActivityObservation.registration(for: T.self, identifier: identifier)
        )
        return copy
    }

    @available(iOS 16.2, *)
    public func register<T: ActivityAttributes>(_ type: T.Type, identifier: String) -> Self {
        var copy = self
        copy.config.registrations.append(
            LiveActivityObservation.registration(for: T.self, identifier: identifier)
        )
        return copy
    }
    #endif

    // MARK: - Build

    public func build() -> LiveActivityConfig {
        config
    }
}
