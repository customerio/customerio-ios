import CioInternalCommon
import Foundation
import UIKit

/// Configuration options for the Geofence module.
public struct GeofenceModuleConfig: CustomerIOModuleConfig {
    /// How the module acquires the device location it needs for geofencing. Default is `.automatic`.
    public let locationMode: GeofenceLocationMode

    public init(locationMode: GeofenceLocationMode = .automatic) {
        self.locationMode = locationMode
    }
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

    public func initialize() {
        GeofenceModuleState.shared.setup(di: DIGraphShared.shared, locationMode: config.locationMode)
    }

    /// Bootstraps geofence cold-wake delivery. Call from the host's `AppDelegate`.
    ///
    /// Wrapper SDKs (React Native, Flutter) don't run `CustomerIO.initialize` in a cold-wake
    /// process, since no JS/Dart runtime starts. This reads persisted state, wires region
    /// monitoring and flushes queued transitions without any module's `initialize` having run.
    ///
    /// Safe to call on every launch. After `CustomerIO.initialize(withConfig:)` it reuses the
    /// same instances, so nothing is initialized or monitored twice.
    ///
    /// - Parameter launchOptions: the launch options the app delegate received.
    @MainActor
    public static func bootstrapForBackgroundDelivery(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        let di = DIGraphShared.shared
        // Only a cold wake is recorded here: a normal launch already logs `module.init`, and only
        // this path sees `launchOptions`.
        if launchOptions?[.location] != nil {
            di.logger.geofenceModuleWoke(launchReason: .locationEvent)
        }
        GeofenceBootstrap.emitDiscoverabilityLogIfNeeded(di: di)
        Task { await di.geofenceEventTracker.flushPending() }
        Task { @MainActor in
            await GeofenceBootstrap.wireMonitor(di: di)
        }
    }
}
