import CioInternalCommon
import CioLocation
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
    func setup(di: DIGraphShared) {
        lock.lock()
        defer { lock.unlock() }
        guard !didSetup else { return }
        didSetup = true

        registerEventSubscriptions(di: di)
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

    /// Invoked on identify. Picks the anchor to refresh from, arming the first-run rearm when no
    /// anchor is available so the next fix fires `refresh` once.
    private func refreshGeofencesIfPossible(di: DIGraphShared) {
        // Arm synchronously before the async reads so a concurrent `LocationAcquiredEvent` can't
        // slip between spawning the Task and the flag write and miss the arm. Cleared below once
        // an anchor is found.
        lastSkippedForNoLocation.wrappedValue = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Prefer the last registration center (walked by movement EXITs) over the Location
            // cache. Movement never updates that cache, so on relaunch it is stale — anchoring a
            // refresh there ranks from a far-away old fix and clobbers the good registration with
            // an empty set. Fall back to the cache only before anything is registered (first run).
            let registrationCenter = await di.geofenceStorage.getLastRegistrationCenter()
            let cached = await self.locationServicesProvider().getLastKnownLocation()
            guard let anchor = registrationCenter ?? cached else { return }
            self.lastSkippedForNoLocation.wrappedValue = false
            _ = await di.geofenceSyncCoordinator.refresh(
                latitude: anchor.latitude,
                longitude: anchor.longitude
            )
        }
    }

    /// Rising-edge CAS — fires `refresh` only on the first fix after an arming skip.
    /// Subsequent fixes from a streaming-location host won't trigger refresh storms.
    private func rearmFirstRunRefreshIfArmed(location: LocationData, di: DIGraphShared) {
        let wasArmed = lastSkippedForNoLocation.mutating { armed in
            let was = armed
            armed = false
            return was
        }
        guard wasArmed else { return }
        di.logger.geofenceFirstRunRearm()
        Task { @MainActor in
            _ = await di.geofenceSyncCoordinator.refresh(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }
}
