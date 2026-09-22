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
    /// Bumped by every reset, so a decision can tell whether the user it started for is still here.
    private let identityEpoch = Synchronized<Int>(0)

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
        // Under one lock with the epoch bump, so a concurrent consume sees all three or none.
        armingLock.withLock {
            explicitRefreshRequested.wrappedValue = false
            lastSkippedForNoLocation.wrappedValue = false
            identityEpoch.mutating { $0 += 1 }
        }
        Task { @MainActor [coordinator] in
            _ = await coordinator().reset()
        }
    }

    /// Refreshes only when something armed for it; one fix is consumed once.
    func onLocationAcquired(_ location: LocationData) {
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
        Task { @MainActor [coordinator] in
            _ = await coordinator().refresh(latitude: location.latitude, longitude: location.longitude, anchorIsLiveFix: true)
        }
    }

    // MARK: - The decision

    private func refreshIfPossible() {
        guard contextStore.currentUserId?.isEmpty == false else { return }
        let startedInEpoch = identityEpoch.wrappedValue
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Registration centre over the Location cache: movement EXITs walk the former and never
            // update the latter, so on relaunch the cache is the stale one.
            let registrationCenter = await self.storage.getLastRegistrationCenter()
            let lastKnown = await self.lastKnownLocation()
            // A reset landed while those two reads were in flight. This decision belongs to a user
            // who has since signed out: arming for them leaves the next user's first fix already
            // spent, and refreshing for them sends the signed-out anchor.
            guard self.identityEpoch.wrappedValue == startedInEpoch else { return }
            guard let anchor = registrationCenter ?? lastKnown else {
                // Armed only here, after the reads, or an existing anchor would arm it falsely.
                self.lastSkippedForNoLocation.wrappedValue = true
                self.autoAcquireIfNeeded()
                return
            }
            self.lastSkippedForNoLocation.wrappedValue = false
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
