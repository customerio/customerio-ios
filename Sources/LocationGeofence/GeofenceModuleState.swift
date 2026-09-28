import CioInternalCommon
@_spi(Geofence) import CioLocation
import Foundation

/// Wires the Geofence module; the refresh decisions live in `GeofenceRefreshTrigger`.
///
/// Lives for the process lifetime via `shared`, because the SDK does not retain the
/// `GeofenceModule` facade once `initialize()` returns.
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
            // Setup usually runs before `identify`, so `wireMonitor` leaves visits off for a nil
            // user. This is what arms them on the ordinary launch order.
            Task { @MainActor in await GeofenceBootstrap.armVisitMonitoring(di: di) }
            trigger.onIdentified()
        }
        di.eventBusHandler.addObserver(ResetEvent.self) { _ in
            trigger.onReset()
            // Disarms visits. Queued after `onReset`, which starts the coordinator reset on the
            // same actor.
            Task { @MainActor in await GeofenceBootstrap.armVisitMonitoring(di: di) }
        }
        di.eventBusHandler.addObserver(LocationAcquiredEvent.self) { event in
            // The only place a position arrives on this platform; every other `location.fix` is a read.
            di.logger.geofenceLocationArrived(event.location)
            trigger.onLocationAcquired(event.location)
        }
    }

    /// Arms a host-initiated refresh so the next acquired fix drives a sync. Writes the shared box
    /// directly because it may be called before `setup`, when no trigger exists.
    func onRefreshRequested() {
        explicitRefreshRequested.wrappedValue = true
    }
}
