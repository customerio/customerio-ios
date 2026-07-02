import CioInternalCommon
@_spi(Geofence) import CioLocation
import Foundation

/// Holds the Geofence module's runtime state and performs one-time setup.
///
/// Lives for the process lifetime via `shared` so the first-run rearm gate outlives
/// `GeofenceModule.initialize()` — the SDK does not retain the module facade once
/// initialization returns.
final class GeofenceModuleState {
    static let shared = GeofenceModuleState()

    /// Resolved lazily at each use so the live `LocationServices` is read even when the geofence
    /// module initializes before `LocationModule` (registration order is not guaranteed).
    private let locationServicesProvider: () -> LocationServices
    /// True when a refresh skipped because no cached location was available. Re-armed
    /// (CAS true→false) on the next location fix so the first GPS update still drives the
    /// initial geofence registration.
    private let lastSkippedForNoLocation = Synchronized<Bool>(false)
    /// Set by a host-initiated `refreshFromCurrentLocation()`. The next acquired fix drives a
    /// refresh regardless of the no-location rearm flag, so a manual refresh works even when it
    /// does not coincide with a first-run no-anchor skip.
    private let explicitRefreshRequested = Synchronized<Bool>(false)
    /// How the module acquires location (`.automatic` self-acquires; `.manual` waits for the host).
    /// Set during `setup`; defaults to `.automatic` until then.
    private let locationMode = Synchronized<GeofenceLocationMode>(.automatic)
    private let lock = NSLock()
    private var didSetup = false

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
        self.locationMode.wrappedValue = locationMode

        registerEventSubscriptions(di: di)
        // Run the refresh decision once at app launch (SDK/module init) so time-staleness and any
        // missed movement EXIT are caught on cold start. Anchors at the last registration center
        // (no GPS) when available; otherwise `.automatic` acquires a fix. Later refreshes come from
        // identify and fresh location fixes.
        refreshGeofencesIfPossible(di: di)
        Task { await di.geofenceEventTracker.flushPending() }
        Task { @MainActor in
            await GeofenceBootstrap.wireMonitor(di: di)
        }
    }

    private func registerEventSubscriptions(di: DIGraphShared) {
        di.eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { [weak self] _ in
            Task { await di.geofenceEventTracker.flushPending() }
            self?.refreshGeofencesIfPossible(di: di)
        }
        di.eventBusHandler.addObserver(ResetEvent.self) { _ in
            Task { @MainActor in
                _ = await di.geofenceSyncCoordinator.reset()
            }
        }
        // Rearm first-run refresh on the first fresh fix after an identify skipped for no anchor.
        di.eventBusHandler.addObserver(LocationAcquiredEvent.self) { [weak self] event in
            self?.rearmFirstRunRefreshIfArmed(location: event.location, di: di)
        }
    }

    /// Arms a host-initiated refresh so the next acquired fix drives a sync even without a prior
    /// no-location skip. Paired with `LocationServices.requestLocationUpdateSilently()` by the
    /// `CustomerIO.geofence.refreshFromCurrentLocation()` facade.
    func onRefreshRequested() {
        explicitRefreshRequested.wrappedValue = true
    }

    /// Invoked at app launch and on identify. Picks the anchor to refresh from, arming the
    /// first-run rearm only when no anchor is available so the next fix fires `refresh` once.
    private func refreshGeofencesIfPossible(di: DIGraphShared) {
        // Geofencing needs an identified user to sync, so don't refresh or self-acquire a fix when
        // none is known (fresh launch before identify) — a later identify re-triggers this.
        guard di.backgroundDeliveryContextStore.currentUserId?.isEmpty == false else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Prefer the last registration center (walked by movement EXITs) over the Location
            // cache. Movement never updates that cache, so on relaunch it is stale — anchoring a
            // refresh there ranks from a far-away old fix and clobbers the good registration with
            // an empty set. Fall back to the last-known fix only before anything is registered.
            let registrationCenter = await di.geofenceStorage.getLastRegistrationCenter()
            let lastKnown = await self.locationServicesProvider().getLastKnownLocation()
            guard let anchor = registrationCenter ?? lastKnown else {
                // No location yet: arm so the next fix drives the first refresh, and in `.automatic`
                // acquire one ourselves (its `LocationAcquiredEvent` fires the armed rearm). Arming
                // only here — not before the async reads — avoids a false arm when an anchor exists.
                self.lastSkippedForNoLocation.wrappedValue = true
                self.autoAcquireIfNeeded()
                return
            }
            self.lastSkippedForNoLocation.wrappedValue = false
            _ = await di.geofenceSyncCoordinator.refresh(
                latitude: anchor.latitude,
                longitude: anchor.longitude
            )
        }
    }

    /// In `.automatic`, requests a silent (no-analytics) fix so geofencing self-bootstraps without
    /// the host calling `refreshFromCurrentLocation()`. No-op in `.manual`, and no-op without
    /// location permission (the Location module gates on it).
    private func autoAcquireIfNeeded() {
        guard locationMode.wrappedValue == .automatic else { return }
        locationServicesProvider().requestLocationUpdateSilently()
    }

    /// Fires `refresh` on a host-initiated refresh or on the first fix after a no-anchor skip, then
    /// clears both flags so a single fix is consumed once. Subsequent fixes from a streaming-location
    /// host won't trigger refresh storms.
    private func rearmFirstRunRefreshIfArmed(location: LocationData, di: DIGraphShared) {
        let requested = explicitRefreshRequested.mutating { requested in
            let was = requested
            requested = false
            return was
        }
        let wasArmed = lastSkippedForNoLocation.mutating { armed in
            let was = armed
            armed = false
            return was
        }
        guard requested || wasArmed else { return }
        di.logger.geofenceFirstRunRearm()
        Task { @MainActor in
            _ = await di.geofenceSyncCoordinator.refresh(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }
}
