import CioInternalCommon
import CioLocation
import Foundation

/// Holds the Geofence module's runtime state and performs one-time setup.
///
/// Lives for the process lifetime via `shared` so the foreground observer token and the
/// first-run rearm gate outlive `GeofenceModule.initialize()` — the SDK does not retain the
/// module facade once initialization returns.
final class GeofenceModuleState {
    static let shared = GeofenceModuleState()

    private let lifecycleNotifying: AppLifecycleNotifying
    /// Resolved lazily at each use so the live `LocationServices` is read even when the geofence
    /// module initializes before `LocationModule` (registration order is not guaranteed).
    private let locationServicesProvider: () -> LocationServices
    /// Retains the foreground observer registered for geofence refresh.
    private var foregroundToken: AppLifecycleObserverToken?
    /// True when a refresh skipped because no cached location was available. Re-armed
    /// (CAS true→false) on the next location fix so the first GPS update still drives the
    /// initial geofence registration.
    private let lastSkippedForNoLocation = Synchronized<Bool>(false)
    private let lock = NSLock()
    private var didSetup = false

    /// Internal init lets tests build instances independent of `.shared`.
    init(
        lifecycleNotifying: AppLifecycleNotifying = RealAppLifecycleNotifying(),
        locationServicesProvider: @escaping () -> LocationServices = { CustomerIO.location }
    ) {
        self.lifecycleNotifying = lifecycleNotifying
        self.locationServicesProvider = locationServicesProvider
    }

    /// Wires the geofence module: event subscriptions, cold-wake pending-flush, foreground
    /// refresh, first-run rearm, and OS monitor bootstrap. Idempotent across repeat calls.
    func setup(di: DIGraphShared) {
        lock.lock()
        defer { lock.unlock() }
        guard !didSetup else { return }
        didSetup = true

        registerEventSubscriptions(di: di)
        Task { await di.geofenceEventTracker.flushPending() }
        // Foreground geofence refresh is intentionally mode-independent — geofence monitoring
        // runs even when location tracking is disabled. Skips silently with no cached anchor;
        // movement EXIT drives the first registration in that case.
        foregroundToken = lifecycleNotifying.addDidBecomeActiveObserver { [weak self] in
            self?.refreshGeofencesIfPossible(di: di)
        }
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
        // Rearm first-run refresh on the first fresh fix after an identify/foreground skip.
        di.eventBusHandler.addObserver(LocationAcquiredEvent.self) { [weak self] event in
            self?.rearmFirstRunRefreshIfArmed(location: event.location, di: di)
        }
    }

    /// Shared by the identify and foreground triggers. Reads the SDK's last known location
    /// through the public Location API; arms the first-run rearm when none is available so
    /// the next fix fires `refresh` once.
    private func refreshGeofencesIfPossible(di: DIGraphShared) {
        // Arm synchronously before the async cache read so a concurrent `LocationAcquiredEvent`
        // can't slip between spawning the Task and the flag write and miss the arm. Cleared
        // below once a cached location is found.
        lastSkippedForNoLocation.wrappedValue = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let location = await self.locationServicesProvider().getLastKnownLocation() else { return }
            self.lastSkippedForNoLocation.wrappedValue = false
            _ = await di.geofenceSyncCoordinator.refresh(
                latitude: location.latitude,
                longitude: location.longitude
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
