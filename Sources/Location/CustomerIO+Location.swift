import CioInternalCommon
import CoreLocation
import Foundation
import UIKit

/// Extension to access the Location module through CustomerIO.
public extension CustomerIO {
    private static var locationServices: LocationServices = UninitializedLocationServices(logger: DIGraphShared.shared.logger)
    private static let lock = NSLock()

    /// Initialize the Location module. Call once after initializing the Customer.io SDK.
    /// Must be called on the main thread so CLLocationManager and related setup are created on main.
    /// In debug builds, calling from a background thread triggers an assertion failure.
    /// In release, calling from a background thread logs an error and schedules initialization on main (no crash).
    ///
    /// Use `LocationConfig(mode:)` with `.off`, `.manual`, or `.onAppStart`. With `.onAppStart`, the SDK requests location once per app launch when the app becomes active (when permission is granted). The SDK stops any in-flight location request automatically when the app enters background.
    ///
    /// **Example:**
    /// ```swift
    /// CustomerIO.initializeLocation(withConfig: LocationConfig(mode: .onAppStart))
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
        registerLocationEventSubscriptions(coordinator: coordinator, eventBusHandler: di.eventBusHandler)
        let locationProvider = CoreLocationProvider(logger: di.logger)
        let implementation = LocationServicesImplementation(
            config: config,
            logger: di.logger,
            locationProvider: locationProvider,
            locationSyncCoordinator: coordinator,
            lifecycleNotifying: RealAppLifecycleNotifying(),
            applicationStateProvider: RealApplicationStateProvider()
        )
        locationServices = implementation
        Task { await implementation.setUpLifecycleObserver() }
    }

    private static func registerLocationEventSubscriptions(coordinator: LocationSyncCoordinator, eventBusHandler: EventBusHandler) {
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in
            Task { await coordinator.syncCachedLocationIfNeeded() }
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
