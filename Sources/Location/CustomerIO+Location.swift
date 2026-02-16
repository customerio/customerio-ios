import CioInternalCommon
import CoreLocation
import Foundation

/// Extension to access the Location module through CustomerIO.
public extension CustomerIO {
    private static var locationServices: LocationServices = UninitializedLocationServices(logger: DIGraphShared.shared.logger)
    private static let lock = NSLock()

    /// Initialize the Location module. Call once after initializing the Customer.io SDK.
    /// Must be called on the main thread so CLLocationManager and related setup are created on main.
    /// In debug builds, calling from a background thread triggers an assertion failure.
    /// In release, calling from a background thread logs an error and schedules initialization on main (no crash).
    ///
    /// **Example:**
    /// ```swift
    /// CustomerIO.initializeLocation(withConfig: LocationConfig(enableLocationTracking: true))
    /// ```
    static func initializeLocation(withConfig config: LocationConfig) {
        assert(Thread.isMainThread, "CustomerIO.initializeLocation(withConfig:) must be called on the main thread.")
        if !Thread.isMainThread {
            DIGraphShared.shared.logger.error("initializeLocation must be called on main; scheduling initialization on main.")
            DispatchQueue.main.async { doInitialize(config: config) }
            return
        }
        doInitialize(config: config)
    }

    private static func doInitialize(config: LocationConfig) {
        lock.lock()
        defer { lock.unlock() }
        if locationServices is LocationServicesImplementation {
            DIGraphShared.shared.logger.reconfigurationNotSupported()
            return
        }
        let locationProvider = CoreLocationProvider(logger: DIGraphShared.shared.logger)
        locationServices = LocationServicesImplementation(
            config: config,
            logger: DIGraphShared.shared.logger,
            eventBusHandler: DIGraphShared.shared.eventBusHandler,
            locationProvider: locationProvider
        )
    }

    /// Access the Location module. Use after calling `CustomerIO.initializeLocation(withConfig:)`.
    /// Before initialization, returns an implementation that logs an error when used.
    static var location: LocationServices {
        lock.lock()
        defer { lock.unlock() }
        return locationServices
    }
}
