import CioInternalCommon
import Foundation

/// Live Activities module. Register it via `SDKConfigBuilder.addModule(_:)` so it is initialized
/// during `CustomerIO.initialize(withConfig:)`, then access it through ``CustomerIO/liveActivities``.
///
/// **Example:**
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LiveActivitiesModule(config:
///         LiveActivityConfigBuilder()
///             .register(CIOSegmentsAttributes.self)
///             .register(CIOCountdownTimerAttributes.self)
///             .build()))
///     .build()
/// CustomerIO.initialize(withConfig: config)
/// ```
public final class LiveActivitiesModule: CustomerIOModule {
    public let moduleName: String = "LiveActivities"
    private let config: LiveActivityConfig

    public init(config: LiveActivityConfig) {
        self.config = config
    }

    public func initialize() {
        // No main-thread requirement (unlike Location's CLLocationManager): registering event-bus
        // observers and starting ActivityKit observation are thread-agnostic, so we initialize on
        // whatever thread CustomerIO.initialize(withConfig:) ran on — a wrapper initializing off the
        // main thread must still get a working module, not a silently-disabled stub.
        //
        // Live Activities require iOS 16.2+. On older systems the module stays uninitialized (its
        // accessor returns the no-op stub); nothing to observe or seed there.
        if #available(iOS 16.2, *) {
            LiveActivitiesModuleState.shared.performInitialization(config: config)
        }
    }
}
