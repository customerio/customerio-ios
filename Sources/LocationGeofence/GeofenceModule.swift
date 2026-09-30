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

/// Opt-in geofence module. Requires the Location module; register both via
/// `SDKConfigBuilder.addModule(_:)`.
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

    /// Delivers geofence events when the OS wakes the app in the background without
    /// `CustomerIO.initialize` running (e.g. wrapper SDKs whose JS/Dart runtime doesn't start). Call
    /// from the host's `AppDelegate` launch method. Safe to call on every launch, including when
    /// `CustomerIO.initialize` also runs: nothing is set up twice.
    ///
    /// - Parameter launchOptions: the launch options the app delegate received.
    @MainActor
    public static func bootstrapForBackgroundDelivery(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        let di = DIGraphShared.shared
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
