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
    /// Retains the foreground observer registered for geofence refresh.
    private var geofenceForegroundToken: AppLifecycleObserverToken?
    /// True when an identify or foreground trigger skipped because no cached location was
    /// available. Re-armed (CAS true→false) on the next processed location fix so a fresh
    /// install's first GPS update still drives the initial geofence registration.
    private let lastSkippedForNoLocation = Synchronized<Bool>(false)

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
            logger: di.logger
        )
        let locationEnrichmentProvider = LocationProfileEnrichmentProvider(storage: storage, config: config)
        di.profileEnrichmentRegistry.register(locationEnrichmentProvider)
        let lifecycleNotifying = RealAppLifecycleNotifying()

        setupGeofence(
            coordinator: coordinator,
            lastLocationStorage: storage,
            lifecycleNotifying: lifecycleNotifying,
            mode: config.mode,
            di: di
        )

        let locationProvider = CoreLocationProvider(logger: di.logger)
        let implementation = LocationServicesImplementation(
            config: config,
            logger: di.logger,
            locationProvider: locationProvider,
            locationSyncCoordinator: coordinator,
            lifecycleNotifying: lifecycleNotifying,
            applicationStateProvider: RealApplicationStateProvider()
        )
        services = implementation
        Task { await implementation.setUpLifecycleObserver() }
    }

    /// Wires the geofence side of the Location module: event subscriptions, cold-wake
    /// pending-flush, foreground refresh, first-run rearm, and OS monitor bootstrap.
    func setupGeofence(
        coordinator: LocationSyncCoordinator,
        lastLocationStorage: LastLocationStorage,
        lifecycleNotifying: AppLifecycleNotifying,
        mode: LocationTrackingMode,
        di: DIGraphShared
    ) {
        registerEventSubscriptions(coordinator: coordinator, lastLocationStorage: lastLocationStorage, mode: mode, di: di)
        Task { await di.geofenceEventTracker.flushPending() }
        // Foreground geofence refresh is intentionally mode-independent — geofence
        // monitoring runs even when `LocationConfig.mode` disables periodic location
        // updates. Skips silently with no cached anchor; movement EXIT drives the first
        // registration in that case.
        geofenceForegroundToken = lifecycleNotifying.addDidBecomeActiveObserver { [weak self] in
            self?.refreshGeofencesIfPossible(lastLocationStorage: lastLocationStorage)
        }
        // Rearm first-run refresh on the first fresh fix after an identify/foreground skip.
        Task {
            await coordinator.setOnLocationProcessed { [weak self] location in
                self?.rearmFirstRunRefreshIfArmed(location: location, di: di)
            }
        }
        Task { @MainActor in
            await GeofenceBootstrap.wireMonitor(di: di)
        }
    }

    private func registerEventSubscriptions(
        coordinator: LocationSyncCoordinator,
        lastLocationStorage: LastLocationStorage,
        mode: LocationTrackingMode,
        di: DIGraphShared
    ) {
        di.eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [weak self] _ in
            Task { await coordinator.syncCachedLocationIfNeeded() }
            Task { await di.geofenceEventTracker.flushPending() }
            self?.refreshGeofencesIfPossible(lastLocationStorage: lastLocationStorage)
            // `.onAppStart`'s lifecycle one-shot fires per process, but `resetContext()`
            // wipes the cached location on sign-out — a subsequent identify in the same
            // process otherwise leaves the first-run rearm armed indefinitely. Forcing a
            // fresh fix here lets `onLocationProcessed` drive the geofence rearm.
            if mode == .onAppStart, lastLocationStorage.getCachedLocation() == nil {
                self?.current.requestLocationUpdate()
            }
        }
        di.eventBusHandler.addObserver(ResetEvent.self) { _ in
            Task { @MainActor in
                _ = await di.geofenceSyncCoordinator.reset()
            }
        }
    }

    /// Shared by the identify and foreground triggers. Mode-independent — geofence
    /// registration is orthogonal to the location-tracking pipeline that populates
    /// `LastLocationStorage` for enrichment. Arms the first-run rearm when no cached
    /// location is available; the next processed fix will fire `refresh` once.
    private func refreshGeofencesIfPossible(lastLocationStorage: LastLocationStorage) {
        guard let location = lastLocationStorage.getCachedLocation() else {
            lastSkippedForNoLocation.wrappedValue = true
            return
        }
        Task { @MainActor in
            _ = await DIGraphShared.shared.geofenceSyncCoordinator.refresh(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }

    /// Rising-edge CAS — fires `refresh` only on the first fix after an arming skip.
    /// Subsequent fixes from a streaming-location host won't trigger refresh storms.
    private func rearmFirstRunRefreshIfArmed(location: LocationData, di: DIGraphShared) {
        let wasArmed = lastSkippedForNoLocation.mutating { armed in
            let was = armed
            armed = false
            return was
        }
        guard wasArmed else { return }
        di.logger.geofenceFirstRunRearm()
        Task { @MainActor in
            _ = await di.geofenceSyncCoordinator.refresh(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }

    /// The current Location services instance. Before initialization, returns an implementation that logs an error when used.
    var current: LocationServices {
        lock.lock()
        defer { lock.unlock() }
        return services
    }
}
