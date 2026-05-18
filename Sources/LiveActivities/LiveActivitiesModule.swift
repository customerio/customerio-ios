import CioInternalCommon
import Foundation

/// Live Activities module for the Customer.io SDK.
///
/// Call `initialize` after `CustomerIO.initialize(withConfig:)` and hold the returned
/// instance for the lifetime of your app:
/// ```swift
/// CustomerIO.initialize(withConfig: config)
/// let liveActivities = LiveActivitiesModule.initialize(
///     LiveActivityConfigBuilder(baseURL: URL(string: "https://…")!)
///         .build()
/// )
/// ```
public final class LiveActivitiesModule {
    private let config: LiveActivityConfig
    private let sdk: CIOLiveActivitiesSDKProviding
    private let tokenStorage: LiveActivityTokenStorage

    // MARK: - Public entry point

    /// Initialize the Live Activities module.
    ///
    /// Call this after `CustomerIO.initialize(withConfig:)`. Hold the returned instance
    /// for the lifetime of your app — it is not a singleton.
    ///
    /// - Parameter config: Module configuration built via `LiveActivityConfigBuilder`.
    /// - Returns: The initialized module instance.
    @discardableResult
    public static func initialize(_ config: LiveActivityConfig) -> LiveActivitiesModule {
        let module = LiveActivitiesModule(
            config: config,
            sdk: CustomerIO.shared,
            tokenStorage: FileActivityTokenStore()
        )
        module.performInitialization()
        return module
    }

    // MARK: - Internal inits (for testing)

    init(
        config: LiveActivityConfig,
        sdk: CIOLiveActivitiesSDKProviding,
        tokenStorage: LiveActivityTokenStorage
    ) {
        self.config = config
        self.sdk = sdk
        self.tokenStorage = tokenStorage
    }

    // MARK: - Private

    private func performInitialization() {
        sdk.logger.debug("LiveActivities module initialized.", "LiveActivities")
        // Activity type observation and event bus wiring go here in the next PR.
    }
}
