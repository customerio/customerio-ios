import CioInternalCommon
import Foundation

/// Decides when a geofence sync runs, and which position it runs from. `GeofenceModuleState` keeps
/// the wiring and hands the two OS-facing reads in as closures.
final class GeofenceRefreshTrigger {
    private let storage: GeofenceStorage
    private let contextStore: BackgroundDeliveryContextStore
    private let coordinator: @MainActor () -> GeofenceSyncCoordinator
    private let logger: Logger
    private let locationMode: GeofenceLocationMode
    /// Resolved at each use: the geofence module can initialize before `LocationModule`.
    private let lastKnownLocation: () async -> LocationData?
    private let acquireFix: () -> Void

    /// Owned by `GeofenceModuleState`: `refreshFromCurrentLocation()` can arrive before `setup`.
    private let explicitRefreshRequested: Synchronized<Bool>
    /// Armed when a refresh found no anchor; the next fix consumes it.
    private let lastSkippedForNoLocation = Synchronized<Bool>(false)
    /// Guards the *pair* of arm flags, not either one of them.
    ///
    /// Both are individually thread-safe, which is not the same as consuming them together. A reset
    /// landing between the two reads in `onLocationAcquired` left the first flag's pre-reset value
    /// in hand and the second already cleared, and the signed-out user's refresh went ahead.
    private let armingLock = NSRecursiveLock()

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

    /// App launch.
    func onModuleInit(launchReason: GeofenceLaunchReason = .appStart) {
        logger.geofenceModuleInitialized(launchReason: launchReason)
        refreshIfPossible()
    }

    func onIdentified() {
        logger.geofenceIdentityChanged(identified: true)
        refreshIfPossible()
    }

    func onReset() {
        logger.geofenceIdentityChanged(identified: false)
        // Synchronously, before the async reset: must land before a re-login's identify re-arms.
        // Under the arming lock so a concurrent consume sees both flags cleared together.
        armingLock.withLock {
            explicitRefreshRequested.wrappedValue = false
            lastSkippedForNoLocation.wrappedValue = false
        }
        Task { @MainActor [coordinator] in
            _ = await coordinator().reset()
        }
    }

    /// Refreshes only when something armed for it; one fix is consumed once.
    func onLocationAcquired(_ location: LocationData) {
        let startedForUser = contextStore.currentUserId
        let wasArmed = armingLock.withLock { () -> Bool in
            let requested = explicitRefreshRequested.mutating { requested in
                let was = requested
                requested = false
                return was
            }
            let skipped = lastSkippedForNoLocation.mutating { armed in
                let was = armed
                armed = false
                return was
            }
            return requested || skipped
        }
        guard wasArmed else { return }
        logger.geofenceFirstRunRearm()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The armed refresh belongs to whoever was current when the flag was consumed. A sign-out
            // (or switch) racing this fix must not let it register for a gone session: the coordinator's
            // reset is superseded while a user is signed in and would not undo this live-fix refresh.
            guard self.contextStore.currentUserId == startedForUser else { return }
            _ = await self.coordinator().refresh(latitude: location.latitude, longitude: location.longitude, anchorIsLiveFix: true)
        }
    }

    // MARK: - The decision

    private func refreshIfPossible() {
        guard let startedForUser = contextStore.currentUserId, !startedForUser.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Registration centre over the Location cache: movement EXITs walk the former and never
            // update the latter, so on relaunch the cache is the stale one.
            let registrationCenter = await self.storage.getLastRegistrationCenter()
            let lastKnown = await self.lastKnownLocation()
            let anchor = registrationCenter ?? lastKnown
            // Identity may have changed while those two reads were in flight. Compare against the
            // CURRENT user, not an epoch counter: a late reset for a prior user must not abort this
            // decision (that left the new user with no geofences), while a genuine sign-out or switch
            // does. The arming write stays under `armingLock` so a concurrent `onReset` clearing the
            // flags and this arming them cannot interleave.
            let isCurrent = self.armingLock.withLock { () -> Bool in
                guard self.contextStore.currentUserId == startedForUser else { return false }
                // Armed only here, after the reads, or an existing anchor would arm it falsely.
                self.lastSkippedForNoLocation.wrappedValue = anchor == nil
                return true
            }
            guard isCurrent else { return }
            guard let anchor else {
                self.autoAcquireIfNeeded()
                return
            }
            // Not a live fix: `anchor` is the stored registration centre (or, before anything is
            // registered, the last-known cache), so the movement trigger must not be sized to a
            // polygon boundary around it.
            _ = await self.coordinator().refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: false)
        }
    }

    private func autoAcquireIfNeeded() {
        guard locationMode == .automatic else { return }
        acquireFix()
    }
}
