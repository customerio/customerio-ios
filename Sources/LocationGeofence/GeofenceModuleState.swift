import CioInternalCommon
@_spi(Geofence) import CioLocation
import Foundation

/// Wires the Geofence module and holds it for the process lifetime.
///
/// Deliberately thin. Every rule about *when* a sync should run lives in
/// `GeofenceRefreshTrigger`, which needs no `DIGraphShared` and no CoreLocation; what is left here
/// is the wiring that does: event-bus subscriptions, the `.shared` singleton, and the live
/// `LocationServices`.
///
/// Lives for the process lifetime via `shared` so the first-run rearm gate outlives
/// `GeofenceModule.initialize()` — the SDK does not retain the module facade once
/// initialization returns.
final class GeofenceModuleState {
    static let shared = GeofenceModuleState()

    /// Resolved lazily at each use so the live `LocationServices` is read even when the geofence
    /// module initializes before `LocationModule` (registration order is not guaranteed).
    private let locationServicesProvider: () -> LocationServices

    /// Owned here rather than by the trigger because `refreshFromCurrentLocation()` can arrive
    /// before `setup` — the box is handed to the trigger, so an early request is not lost.
    private let explicitRefreshRequested = Synchronized<Bool>(false)

    private let lock = NSLock()
    private var didSetup = false
    /// Built in `setup`, once the DI graph exists.
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
            // The only place a position *arrives* on this platform. Everything else recorded as
            // `location.fix` is the SDK pulling `CLLocationManager.location`, which is a query, not
            // an event — and until this record existed a capture showed 43 pulls and no arrivals,
            // so a replay could only reproduce the sync that follows by pretending a read was a
            // delivery. Android logs the same channel as `prov=bus`.
            //
            // Accuracy and age are absent: `LocationAcquiredEvent` carries coordinates only, and
            // widening a core event to enrich a diagnostic would be a contract change, not a
            // logging one.
            di.logger.geofenceLocationArrived(event.location)
            trigger.onLocationAcquired(event.location)
        }
    }

    /// Arms a host-initiated refresh so the next acquired fix drives a sync even without a prior
    /// no-location skip. Paired with `LocationServices.requestLocationUpdateSilently()` by the
    /// `CustomerIO.geofence.refreshFromCurrentLocation()` facade.
    ///
    /// Writes the shared box directly: this can be called before `setup`, when no trigger exists.
    func onRefreshRequested() {
        explicitRefreshRequested.wrappedValue = true
    }
}
