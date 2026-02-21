import CioInternalCommon
import Foundation

/// Location module that can be registered via `SDKConfigBuilder.addModule(_:)` so Location is initialized during `CustomerIO.initialize(withConfig:)`.
///
/// **Example:**
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LocationModule(config: LocationConfig(enableLocationTracking: true)))
///     .build()
/// CustomerIO.initialize(withConfig: config)
/// ```
public final class LocationModule: CustomerIOModule {
    public let moduleName: String = "Location"
    private let config: LocationConfig

    public init(config: LocationConfig) {
        self.config = config
    }

    public func initialize() {
        if Thread.isMainThread {
            CustomerIO.performLocationInitialization(config: config)
        } else {
            DIGraphShared.shared.logger.error("Location module initialize() called off main thread; scheduling on main.")
            DispatchQueue.main.async { [config] in
                CustomerIO.performLocationInitialization(config: config)
            }
        }
    }
}
