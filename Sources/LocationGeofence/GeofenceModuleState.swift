import CioInternalCommon
@_spi(Geofence) import CioLocation
import Foundation

/// Process-lifetime via `shared`: the SDK doesn't retain `GeofenceModule` after `initialize()`.
final class GeofenceModuleState {
    static let shared = GeofenceModuleState()

    /// Resolved at each use: this module may initialize before `LocationModule`.
    private let locationServicesProvider: () -> LocationServices

    /// Owned here because `refreshFromCurrentLocation()` can arrive before `setup`.
    private let explicitRefreshRequested = Synchronized<Bool>(false)

    private let lock = NSLock()
    private var didSetup = false
    private var trigger: GeofenceRefreshTrigger?

    init(
        locationServicesProvider: @escaping () -> LocationServices = { CustomerIO.location }
    ) {
        self.locationServicesProvider = locationServicesProvider
    }

    /// Idempotent: only the first call wires anything.
    func setup(di: DIGraphShared, locationMode: GeofenceLocationMode = .automatic) {
        lock.lock()
        defer { lock.unlock() }
        guard !didSetup else { return }
        didSetup = true

        let trigger = GeofenceRefreshTrigger(
            storage: di.geofenceStorage,
            contextStore: di.backgroundDeliveryContextStore,
            coordinator: { di.geofenceSyncCoordinator },
            logger: di.logger,
            locationMode: locationMode,
            explicitRefreshRequested: explicitRefreshRequested,
            lastKnownLocation: { [locationServicesProvider] in
                await locationServicesProvider().getLastKnownLocation()
            },
            acquireFix: { [locationServicesProvider] in
                locationServicesProvider().requestLocationUpdateSilently()
            }
        )
        self.trigger = trigger

        registerEventSubscriptions(di: di, trigger: trigger)
        trigger.onModuleInit()
        Task { await di.geofenceEventTracker.flushPending() }
        Task { @MainActor in
            await GeofenceBootstrap.wireMonitor(di: di)
        }
    }

    private func registerEventSubscriptions(di: DIGraphShared, trigger: GeofenceRefreshTrigger) {
        di.eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { _ in
            Task { await di.geofenceEventTracker.flushPending() }
            // `wireMonitor` usually ran before identify and left visits off; this arms them.
            Task { @MainActor in await GeofenceBootstrap.armVisitMonitoring(di: di) }
            trigger.onIdentified()
        }
        di.eventBusHandler.addObserver(ResetEvent.self) { _ in
            trigger.onReset()
            // Disarms visits. Must stay after `onReset`, which starts the reset on the same actor.
            Task { @MainActor in await GeofenceBootstrap.armVisitMonitoring(di: di) }
        }
        di.eventBusHandler.addObserver(LocationAcquiredEvent.self) { event in
            di.logger.geofenceLocationArrived(event.location)
            trigger.onLocationAcquired(event.location)
        }
    }

    /// May be called before `setup`, so it writes the shared box rather than the trigger.
    func onRefreshRequested() {
        explicitRefreshRequested.wrappedValue = true
    }
}
