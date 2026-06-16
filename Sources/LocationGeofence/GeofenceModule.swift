import CioInternalCommon
import Foundation

/// Configuration options for the Geofence module.
///
/// Currently exposes no options; it reserves the configuration entry point so future
/// geofence settings can be added without a source-breaking change to `GeofenceModule`.
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

    public func initialize() {
        // Intentionally empty: this module registers no behavior on its own yet.
    }
}
