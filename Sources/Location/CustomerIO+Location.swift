import CioInternalCommon
import Foundation

/// Extension to access the Location module through CustomerIO.
public extension CustomerIO {
    private static var locationServices: LocationServices = UninitializedLocationServices(logger: DIGraphShared.shared.logger)
    private static let lock = NSLock()

    /// Initialize the Location module. Call once after initializing the Customer.io SDK.
    ///
    /// **Example:**
    /// ```swift
    /// CustomerIO.initializeLocation(withConfig: LocationConfig(enableLocationTracking: true))
    /// ```
    static func initializeLocation(withConfig config: LocationConfig) {
        lock.lock()
        defer { lock.unlock() }
        if locationServices is LocationServicesImplementation {
            DIGraphShared.shared.logger.reconfigurationNotSupported()
            return
        }
        locationServices = LocationServicesImplementation(
            config: config,
            logger: DIGraphShared.shared.logger,
            eventBusHandler: DIGraphShared.shared.eventBusHandler
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
