import CioInternalCommon
import Foundation
import UIKit

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

    /// Bootstraps geofence cold-wake delivery from the host's `AppDelegate`.
    ///
    /// Wrapper SDKs (RN, Flutter) do not run `CustomerIO.initialize` in the cold-wake
    /// process — there is no JS/Dart runtime. This entry reads all the state it needs
    /// from persisted stores and wires up region monitoring + direct-HTTP delivery
    /// without requiring any module's `initialize` to have run in this process.
    ///
    /// Safe to call on every launch. When the SDK has been initialized via
    /// `CustomerIO.initialize(withConfig:)`, the same DI-resolved singletons are
    /// reused — no double-init, no duplicate monitoring.
    @MainActor
    public static func bootstrapForBackgroundDelivery(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        // Reserved for future cold-wake detection (e.g. `launchOptions[.location]`).
        _ = launchOptions

        let di = DIGraphShared.shared
        GeofenceBootstrap.emitDiscoverabilityLogIfNeeded(di: di)
        Task { await di.geofenceEventTracker.flushPending() }
        Task { @MainActor in
            await GeofenceBootstrap.wireMonitor(di: di)
        }
    }
}
