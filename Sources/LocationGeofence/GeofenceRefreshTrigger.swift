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
        explicitRefreshRequested.wrappedValue = false
        lastSkippedForNoLocation.wrappedValue = false
        Task { @MainActor [coordinator] in
            _ = await coordinator().reset()
        }
    }

    /// Refreshes only when something armed for it; one fix is consumed once.
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

    private func refreshIfPossible() {
        guard contextStore.currentUserId?.isEmpty == false else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Registration centre over the Location cache: movement EXITs walk the former and never
            // update the latter, so on relaunch the cache is the stale one.
            let registrationCenter = await self.storage.getLastRegistrationCenter()
            let lastKnown = await self.lastKnownLocation()
            guard let anchor = registrationCenter ?? lastKnown else {
                // Armed only here, after the reads, or an existing anchor would arm it falsely.
                self.lastSkippedForNoLocation.wrappedValue = true
                self.autoAcquireIfNeeded()
                return
            }
            self.lastSkippedForNoLocation.wrappedValue = false
            _ = await self.coordinator().refresh(latitude: anchor.latitude, longitude: anchor.longitude)
        }
    }

    private func autoAcquireIfNeeded() {
        guard locationMode == .automatic else { return }
        acquireFix()
    }
}
