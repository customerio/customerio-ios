import CioInternalCommon
import Foundation

/// Location module that can be registered via `SDKConfigBuilder.addModule(_:)` so Location is initialized during `CustomerIO.initialize(withConfig:)`.
///
/// **Example:**
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LocationModule(config: LocationConfig(mode: .onAppStart)))
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
            LocationModuleState.shared.performInitialization(config: config)
        } else {
            DIGraphShared.shared.logger.error(
                "Location module must be initialized on the main thread. Call CustomerIO.initialize(withConfig:) from the main thread (e.g. from application(_:didFinishLaunchingWithOptions:)).",
                "Location",
                nil
            )
        }
    }
}
