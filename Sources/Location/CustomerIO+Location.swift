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
        let di = DIGraphShared.shared
        let storage = LastLocationStorageImpl(storage: di.sharedKeyValueStorage)
        let filter = LocationFilter(storage: storage, dateUtil: di.dateUtil)
        let coordinator = LocationSyncCoordinator(
            storage: storage,
            filter: filter,
            eventBusHandler: di.eventBusHandler,
            logger: di.logger
        )
        registerLocationEventSubscriptions(coordinator: coordinator, eventBusHandler: di.eventBusHandler)
        let locationProvider = CoreLocationProvider(logger: di.logger)
        locationServices = LocationServicesImplementation(
            config: config,
            logger: di.logger,
            locationProvider: locationProvider,
            locationSyncCoordinator: coordinator
        )
    }

    private static func registerLocationEventSubscriptions(coordinator: LocationSyncCoordinator, eventBusHandler: EventBusHandler) {
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in
            Task { await coordinator.syncCachedLocationIfNeeded() }
        }
        eventBusHandler.addObserver(ResetEvent.self) { _ in
            Task { await coordinator.clearCache() }
        }
        eventBusHandler.addObserver(LocationTrackedEvent.self) { event in
            Task { await coordinator.recordLastSyncWhenTracked(location: event.location, timestamp: event.timestamp) }
        }
    }

    /// Access the Location module. Use after calling `CustomerIO.initializeLocation(withConfig:)`.
    /// Before initialization, returns an implementation that logs an error when used.
    static var location: LocationServices {
        lock.lock()
        defer { lock.unlock() }
        return locationServices
    }
}
