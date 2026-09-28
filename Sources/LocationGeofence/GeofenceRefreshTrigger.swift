import CioInternalCommon
import Foundation

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
    private let lastSkippedForNoLocation = Synchronized<Bool>(false)
    /// Guards the flag *pair*: a reset between the two reads could let a signed-out user's refresh run.
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
        // Synchronous, so it lands before a re-login's identify re-arms.
        armingLock.withLock {
            explicitRefreshRequested.wrappedValue = false
            lastSkippedForNoLocation.wrappedValue = false
        }
        Task { @MainActor [coordinator] in
            _ = await coordinator().reset()
        }
    }

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
            // A racing sign-out/switch must win: the coordinator's reset is skipped while anyone is
            // signed in, so it wouldn't undo this refresh.
            guard self.contextStore.currentUserId == startedForUser else { return }
            _ = await self.coordinator().refresh(latitude: location.latitude, longitude: location.longitude, anchorIsLiveFix: true)
        }
    }

    // MARK: - The decision

    private func refreshIfPossible() {
        guard let startedForUser = contextStore.currentUserId, !startedForUser.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Registration centre first: movement EXITs move it but not the Location cache.
            let registrationCenter = await self.storage.getLastRegistrationCenter()
            let lastKnown = await self.lastKnownLocation()
            let anchor = registrationCenter ?? lastKnown
            // CURRENT user, not an epoch counter: a late reset for a prior user must not abort this.
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
            // Not live: `anchor` is stored.
            _ = await self.coordinator().refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: false)
        }
    }

    private func autoAcquireIfNeeded() {
        guard locationMode == .automatic else { return }
        acquireFix()
    }
}
