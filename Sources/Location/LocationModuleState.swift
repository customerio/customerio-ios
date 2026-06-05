import CioInternalCommon
import CoreLocation
import Foundation
import UIKit

/// Holds the Location module's runtime state and performs one-time initialization.
/// CLLocationManager and related setup are created on the main thread during `performInitialization(config:)`.
final class LocationModuleState {
    static let shared = LocationModuleState()

    private var services: LocationServices = UninitializedLocationServices(logger: DIGraphShared.shared.logger)
    private let lock = NSLock()
    /// Retains the geofence monitor across the process lifetime so CLLocationManager delegate
    /// callbacks land on a live instance. Accessed only from the main actor.
    @MainActor private var geofenceMonitor: GeofenceRegionMonitoring?

    private init() {}

    /// Performs one-time setup of the Location module. Call from main thread (e.g. from `LocationModule.initialize()`).
    func performInitialization(config: LocationConfig) {
        lock.lock()
        defer { lock.unlock() }
        if services is LocationServicesImplementation {
            DIGraphShared.shared.logger.reconfigurationNotSupported()
            return
        }
        let di = DIGraphShared.shared
        let stateStore = FileLastLocationStateStore()
        let storage = LastLocationStorageImpl(stateStore: stateStore)
        let filter = LocationFilter(storage: storage, dateUtil: di.dateUtil)
        let dataPipeline = di.getOptional(DataPipelineTracking.self)
        let coordinator = LocationSyncCoordinator(
            storage: storage,
            filter: filter,
            dataPipeline: dataPipeline,
            dateUtil: di.dateUtil,
            logger: di.logger
        )
        let locationEnrichmentProvider = LocationProfileEnrichmentProvider(storage: storage, config: config)
        di.profileEnrichmentRegistry.register(locationEnrichmentProvider)
        let geofenceStorage = GeofenceStorage()
        let geofenceEventTracker = makeGeofenceEventTracker(di: di, geofenceStorage: geofenceStorage)
        registerEventSubscriptions(
            coordinator: coordinator,
            geofenceEventTracker: geofenceEventTracker,
            eventBusHandler: di.eventBusHandler
        )
        Task { await geofenceEventTracker.flushPending() }
        Task { @MainActor [weak self] in
            // Fetch cache BEFORE constructing the monitor: once CLLocationManager is created,
            // its delegate is live and the OS can deliver queued cold-wake region callbacks.
            // Any `await` between delegate-set and `startMonitoring` would drop those events.
            let geofences = await geofenceStorage.getCachedGeofences()
            let monitor = CoreLocationGeofenceMonitor(logger: di.logger)
            self?.geofenceMonitor = monitor
            GeofenceMonitorBinder.bind(
                monitor: monitor,
                geofences: geofences,
                tracker: geofenceEventTracker
            )
        }
        let locationProvider = CoreLocationProvider(logger: di.logger)
        let implementation = LocationServicesImplementation(
            config: config,
            logger: di.logger,
            locationProvider: locationProvider,
            locationSyncCoordinator: coordinator,
            lifecycleNotifying: RealAppLifecycleNotifying(),
            applicationStateProvider: RealApplicationStateProvider()
        )
        services = implementation
        Task { await implementation.setUpLifecycleObserver() }
    }

    private func registerEventSubscriptions(
        coordinator: LocationSyncCoordinator,
        geofenceEventTracker: GeofenceEventTracker,
        eventBusHandler: EventBusHandler
    ) {
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in
            Task { await coordinator.syncCachedLocationIfNeeded() }
            Task { await geofenceEventTracker.flushPending() }
        }
    }

    private func makeGeofenceEventTracker(di: DIGraphShared, geofenceStorage: GeofenceStorage) -> GeofenceEventTracker {
        let deliveryTracker = GeofenceDeliveryTrackerImpl(
            httpClient: di.backgroundDeliveryHttpClient,
            logger: di.logger
        )
        return GeofenceEventTracker(
            storage: geofenceStorage,
            pendingStore: PendingGeofenceMetricStore(),
            deliveryTracker: deliveryTracker,
            contextStore: di.backgroundDeliveryContextStore,
            eventBusHandler: di.eventBusHandler,
            dateUtil: di.dateUtil,
            logger: di.logger
        )
    }

    /// The current Location services instance. Before initialization, returns an implementation that logs an error when used.
    var current: LocationServices {
        lock.lock()
        defer { lock.unlock() }
        return services
    }
}
