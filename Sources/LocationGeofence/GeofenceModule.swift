import CioInternalCommon
import Foundation
import UIKit

/// Configuration options for the Geofence module. Currently has no options.
public struct GeofenceModuleConfig: CustomerIOModuleConfig {
    public init() {}
}

/// Opt-in on-device geofence module. Depends on the Location module: register both via
/// `SDKConfigBuilder.addModule(_:)` so geofence monitoring is initialized during
/// `CustomerIO.initialize(withConfig:)`. Apps that only need location tracking register
/// `LocationModule` alone and never link this module.
///
/// **Example:**
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LocationModule(config: LocationConfig(mode: .onAppStart)))
///     .addModule(GeofenceModule())
///     .build()
/// CustomerIO.initialize(withConfig: config)
/// ```
public final class GeofenceModule: CustomerIOModule {
    public let moduleName: String = "Geofence"
    private let config: GeofenceModuleConfig

    public init(config: GeofenceModuleConfig = GeofenceModuleConfig()) {
        self.config = config
    }

    /// Setup runs on `GeofenceModuleState.shared`, which lives for the process lifetime — the
    /// SDK does not retain this facade after `initialize()` returns, so the module's foreground
    /// observer and first-run state must outlive it.
    public func initialize() {
        GeofenceModuleState.shared.setup(di: DIGraphShared.shared)
    }

    /// Bootstraps geofence cold-wake delivery from the host's `AppDelegate`.
    ///
    /// Wrapper SDKs (RN, Flutter) do not run `CustomerIO.initialize` in the cold-wake
    /// process — there is no JS/Dart runtime. This entry reads all the state it needs
    /// from persisted stores and wires up region monitoring and flushes any queued
    /// transition deliveries without requiring any module's `initialize` to have run in
    /// this process.
    ///
    /// Safe to call on every launch. When the SDK has been initialized via
    /// `CustomerIO.initialize(withConfig:)`, the same DI-resolved singletons are reused —
    /// no double-init, no duplicate monitoring.
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
