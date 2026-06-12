import CioInternalCommon
import Foundation

/// Holds the Location module's runtime state and performs one-time initialization.
/// CLLocationManager and related setup are created on the main thread during `performInitialization(config:)`.
final class LocationModuleState {
    static let shared = LocationModuleState()

    private var services: LocationServices = UninitializedLocationServices(logger: DIGraphShared.shared.logger)
    private let lock = NSLock()

    /// Internal init lets tests build instances independent of `.shared`.
    init() {}

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
            logger: di.logger,
            eventBusHandler: di.eventBusHandler
        )
        let locationEnrichmentProvider = LocationProfileEnrichmentProvider(storage: storage, config: config)
        di.profileEnrichmentRegistry.register(locationEnrichmentProvider)

        registerEventSubscriptions(coordinator: coordinator, storage: storage, mode: config.mode, di: di)

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
        storage: LastLocationStorage,
        mode: LocationTrackingMode,
        di: DIGraphShared
    ) {
        di.eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [weak self] _ in
            Task { await coordinator.syncCachedLocationIfNeeded() }
            // In `.onAppStart` the per-process one-shot fix already fired; a re-identify after
            // `resetContext()` wiped the cache otherwise leaves no location until the next launch.
            // Requesting a fresh fix keeps the cached location (and any downstream observers) current.
            if mode == .onAppStart, storage.getCachedLocation() == nil {
                self?.current.requestLocationUpdate()
            }
        }
    }

    /// The current Location services instance. Before initialization, returns an implementation that logs an error when used.
    var current: LocationServices {
        lock.lock()
        defer { lock.unlock() }
        return services
    }
}
