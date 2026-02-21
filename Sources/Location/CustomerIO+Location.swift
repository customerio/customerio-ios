import CioInternalCommon
import CoreLocation
import Foundation

/// Extension to access the Location module through CustomerIO.
public extension CustomerIO {
    private static var locationServices: LocationServices = UninitializedLocationServices(logger: DIGraphShared.shared.logger)
    private static let lock = NSLock()

    /// Internal entry point used by `LocationModule.initialize()`. CLLocationManager is created on the main thread.
    static func performLocationInitialization(config: LocationConfig) {
        lock.lock()
        defer { lock.unlock() }
        if locationServices is LocationServicesImplementation {
            DIGraphShared.shared.logger.reconfigurationNotSupported()
            return
        }
        let di = DIGraphShared.shared
        let stateStore = KeychainLastLocationStateStore()
        let storage = LastLocationStorageImpl(stateStore: stateStore)
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

    /// Access the Location module. Register the module via `SDKConfigBuilder.addModule(LocationModule(config: ...))` before `CustomerIO.initialize(withConfig:)` to enable Location.
    /// Before initialization, returns an implementation that logs an error when used.
    static var location: LocationServices {
        lock.lock()
        defer { lock.unlock() }
        return locationServices
    }
}
