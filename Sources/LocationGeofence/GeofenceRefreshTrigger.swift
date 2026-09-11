import CioInternalCommon
import Foundation

/// Decides when a geofence sync runs, and which position it runs from.
///
/// Extracted from `GeofenceModuleState` so these rules can be exercised without a `DIGraphShared`
/// and without CoreLocation. The module state keeps the wiring — event-bus subscriptions, the
/// process-lifetime singleton, the live `LocationServices` — and hands the two OS-facing reads in
/// as closures. Everything here is a decision:
///
/// - whether an identified user exists at all,
/// - which anchor a refresh runs from,
/// - whether to arm for the next fix when there is no anchor,
/// - whether an arriving fix consumes that arming.
final class GeofenceRefreshTrigger {
    private let storage: GeofenceStorage
    private let contextStore: BackgroundDeliveryContextStore
    /// Resolved on the main actor at each use: the DI accessor is main-actor isolated, and
    /// `setup` builds this object from a nonisolated context.
    private let coordinator: @MainActor () -> GeofenceSyncCoordinator
    private let logger: Logger
    /// `.automatic` self-acquires a fix when no anchor exists; `.manual` waits for the host.
    private let locationMode: GeofenceLocationMode
    /// Last position the Location module holds. A closure because the live `LocationServices` is
    /// resolved at each use — the geofence module can initialize before `LocationModule`.
    private let lastKnownLocation: () async -> LocationData?
    /// Requests a silent (no-analytics) fix. The only OS-facing act reachable from this file.
    private let acquireFix: () -> Void

    /// Set by a host-initiated `refreshFromCurrentLocation()`, which can arrive **before** the
    /// module is set up. The box is owned by `GeofenceModuleState` and shared with this object so
    /// a request made that early is still honoured once wiring completes.
    private let explicitRefreshRequested: Synchronized<Bool>
    /// True when a refresh skipped because no cached location was available. Re-armed (CAS
    /// true→false) on the next fix so the first GPS update still drives the initial registration.
    private let lastSkippedForNoLocation = Synchronized<Bool>(false)

    init(
        storage: GeofenceStorage,
        contextStore: BackgroundDeliveryContextStore,
        coordinator: @escaping @MainActor () -> GeofenceSyncCoordinator,
        logger: Logger,
        locationMode: GeofenceLocationMode,
        explicitRefreshRequested: Synchronized<Bool>,
        lastKnownLocation: @escaping () async -> LocationData?,
        acquireFix: @escaping () -> Void
    ) {
        self.storage = storage
        self.contextStore = contextStore
        self.coordinator = coordinator
        self.logger = logger
        self.locationMode = locationMode
        self.explicitRefreshRequested = explicitRefreshRequested
        self.lastKnownLocation = lastKnownLocation
        self.acquireFix = acquireFix
    }

    // MARK: - Inputs

    /// App launch (SDK/module init). Runs the refresh decision once so time-staleness and any
    /// missed movement EXIT are caught on cold start.
    func onModuleInit(launchReason: GeofenceLaunchReason = .appStart) {
        logger.geofenceModuleInitialized(launchReason: launchReason)
        refreshIfPossible()
    }

    /// A user was identified. Everything identity-gated becomes possible here.
    func onIdentified() {
        logger.geofenceIdentityChanged(identified: true)
        refreshIfPossible()
    }

    /// A user signed out.
    func onReset() {
        logger.geofenceIdentityChanged(identified: false)
        // Cleared synchronously, before the async reset: a previous user's pending request must not
        // drive a sync for the next user, and this has to land before a re-login's identify re-arms.
        explicitRefreshRequested.wrappedValue = false
        lastSkippedForNoLocation.wrappedValue = false
        Task { @MainActor [coordinator] in
            _ = await coordinator().reset()
        }
    }

    /// A fresh fix arrived. Drives a refresh only when something armed for it, then clears both
    /// flags so one fix is consumed once — a streaming host must not cause refresh storms.
    func onLocationAcquired(_ location: LocationData) {
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
        logger.geofenceFirstRunRearm()
        Task { @MainActor [coordinator] in
            _ = await coordinator().refresh(latitude: location.latitude, longitude: location.longitude)
        }
    }

    // MARK: - The decision

    /// Picks the anchor to refresh from, arming the first-run rearm only when no anchor is
    /// available so the next fix fires `refresh` once.
    private func refreshIfPossible() {
        // Geofencing needs an identified user to sync, so don't refresh or self-acquire a fix when
        // none is known (fresh launch before identify) — a later identify re-triggers this.
        guard contextStore.currentUserId?.isEmpty == false else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Prefer the last registration center (walked by movement EXITs) over the Location
            // cache. Movement never updates that cache, so on relaunch it is stale — anchoring a
            // refresh there ranks from a far-away old fix and clobbers the good registration with
            // an empty set. Fall back to the last-known fix only before anything is registered.
            let registrationCenter = await self.storage.getLastRegistrationCenter()
            let lastKnown = await self.lastKnownLocation()
            guard let anchor = registrationCenter ?? lastKnown else {
                // No location yet: arm so the next fix drives the first refresh, and in `.automatic`
                // acquire one ourselves (its `LocationAcquiredEvent` fires the armed rearm). Arming
                // only here — not before the async reads — avoids a false arm when an anchor exists.
                self.lastSkippedForNoLocation.wrappedValue = true
                self.autoAcquireIfNeeded()
                return
            }
            self.lastSkippedForNoLocation.wrappedValue = false
            _ = await self.coordinator().refresh(latitude: anchor.latitude, longitude: anchor.longitude)
        }
    }

    /// No-op in `.manual`, and no-op without location permission (the Location module gates on it).
    private func autoAcquireIfNeeded() {
        guard locationMode == .automatic else { return }
        acquireFix()
    }
}
