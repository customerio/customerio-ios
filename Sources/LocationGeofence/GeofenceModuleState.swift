import CioInternalCommon
@_spi(Geofence) import CioLocation
import Foundation

/// Wires the Geofence module and holds it for the process lifetime. The decisions live in
/// `GeofenceRefreshTrigger`; this is the wiring around it.
///
/// Lives for the process lifetime via `shared` so the first-run rearm gate outlives
/// `GeofenceModule.initialize()` — the SDK does not retain the module facade once
/// initialization returns.
final class GeofenceModuleState {
    static let shared = GeofenceModuleState()

    /// Resolved lazily at each use so the live `LocationServices` is read even when the geofence
    /// module initializes before `LocationModule` (registration order is not guaranteed).
    private let locationServicesProvider: () -> LocationServices

    /// Owned here because `refreshFromCurrentLocation()` can arrive before `setup`.
    private let explicitRefreshRequested = Synchronized<Bool>(false)

    private let lock = NSLock()
    private var didSetup = false
    private var trigger: GeofenceRefreshTrigger?

    /// Internal init lets tests build instances independent of `.shared`.
    init(
        locationServicesProvider: @escaping () -> LocationServices = { CustomerIO.location }
    ) {
        self.locationServicesProvider = locationServicesProvider
    }

    /// Wires the geofence module: event subscriptions, cold-wake pending-flush, first-run
    /// rearm, and OS monitor bootstrap. Idempotent across repeat calls.
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
            trigger.onIdentified()
        }
        di.eventBusHandler.addObserver(ResetEvent.self) { _ in
            trigger.onReset()
        }
        // Rearm first-run refresh on the first fresh fix after an identify skipped for no anchor.
        di.eventBusHandler.addObserver(LocationAcquiredEvent.self) { event in
            // The only place a position arrives on this platform; every other `location.fix` is a read.
            di.logger.geofenceLocationArrived(event.location)
            trigger.onLocationAcquired(event.location)
        }
    }

    /// Arms a host-initiated refresh so the next acquired fix drives a sync even without a prior
    /// no-location skip. Paired with `LocationServices.requestLocationUpdateSilently()` by the
    /// `CustomerIO.geofence.refreshFromCurrentLocation()` facade.
    /// Writes the shared box directly: may be called before `setup`, when no trigger exists.
    func onRefreshRequested() {
        explicitRefreshRequested.wrappedValue = true
    }
}
