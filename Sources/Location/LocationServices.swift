import CioInternalCommon
import CoreLocation
import Foundation

// MARK: - LocationServices

/// Protocol for the Location module's public API.
///
/// Use `CustomerIO.location` after registering the module via `SDKConfigBuilder.addModule(LocationModule(config: ...))` and calling `CustomerIO.initialize(withConfig:)`.
///
/// **Example:**
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LocationModule(config: LocationConfig(mode: .onAppStart)))
///     .build()
/// CustomerIO.initialize(withConfig: config)
/// CustomerIO.location.setLastKnownLocation(clLocation)
/// CustomerIO.location.requestLocationUpdate()
/// ```
public protocol LocationServices: AnyObject {
    /// Sets the last known location from the host app's existing location system.
    ///
    /// Use this method when your app already has a location system and you want to
    /// send that location data to Customer.io without the SDK managing location permissions
    /// or CLLocationManager directly.
    ///
    /// **Example:**
    /// ```swift
    /// func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    ///     if let location = locations.last {
    ///         CustomerIO.location.setLastKnownLocation(location)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter location: The CLLocation to track. Must have valid coordinates.
    func setLastKnownLocation(_ location: CLLocation)

    /// Starts a single location update and sends the result to Customer.io (subject to config and permissions).
    /// Work runs in a background task. No-ops if location tracking is disabled or permission not granted.
    ///
    /// The SDK does not request location permission. The host app must prompt for authorization
    /// (e.g. via `CLLocationManager.requestWhenInUseAuthorization()`) and only call this when permission is granted.
    func requestLocationUpdate()

    /// Acquires a one-shot location fix for internal consumers (e.g. geofencing) with no analytics
    /// side effects: no `CIO Location Update` track event, and the fix is **not** persisted or used for
    /// identify context enrichment. It does update the in-memory last-known fix, so it is observable via
    /// `getLastKnownLocation` — geofencing anchors its refresh on that value.
    /// It posts `LocationAcquiredEvent` and runs regardless of `LocationConfig.mode` (geofencing needs
    /// a location even when location tracking is `.off`).
    /// Not part of the customer-facing API — other SDK modules call it via `@_spi(Geofence)`.
    @_spi(Geofence)
    func requestLocationUpdateSilently()

    /// Returns the most recent location the SDK has cached, or `nil` if none is known yet.
    ///
    /// The value comes from `setLastKnownLocation`, a `requestLocationUpdate` result, or a
    /// previous session (the cache is persisted), so a location can be available before any
    /// fix has been received in the current session.
    func getLastKnownLocation() async -> LocationData?
}

// MARK: - UninitializedLocationServices

final class UninitializedLocationServices: LocationServices {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func setLastKnownLocation(_ location: CLLocation) {
        logger.moduleNotInitialized()
    }

    func requestLocationUpdate() {
        logger.moduleNotInitialized()
    }

    func requestLocationUpdateSilently() {
        logger.moduleNotInitialized()
    }

    func getLastKnownLocation() async -> LocationData? {
        logger.moduleNotInitialized()
        return nil
    }
}

// MARK: - LocationServicesImplementation (internal, real implementation)

actor LocationServicesImplementation: LocationServices {
    private let config: LocationConfig
    private let logger: Logger
    private let locationProvider: any LocationProviding
    private let locationSyncCoordinator: LocationSyncCoordinator
    private let lifecycleNotifying: AppLifecycleNotifying
    private let applicationStateProvider: ApplicationStateProvider
    /// Serializes calls from the synchronous `setLastKnownLocation` API so locations are
    /// processed in the same order the host app supplies them.
    private nonisolated let pendingSetLastKnownLocationWork = Synchronized<Task<Void, Never>?>(nil)
    /// Retains the latest fire-and-forget request entry task so tests can join it without sleeps.
    /// Overlap tests observe the earlier request in flight before joining this latest entry.
    private nonisolated let pendingLocationRequestEntryWork = Synchronized<Task<Void, Never>?>(nil)
    /// Retains the latest fire-and-forget stop task so tests can join it without sleeps.
    private nonisolated let pendingStopLocationWork = Synchronized<Task<Void, Never>?>(nil)
    private var currentTask: Task<Void, Never>?
    /// Set when a tracked request arrives while another request is in flight, so the tracked
    /// intent survives the single-request gate (the lifecycle's tracked request and geofence's
    /// silent auto-acquire race at first identified launch).
    private var pendingTrackUpgrade = false
    /// Owned by this implementation; calls requestLocationUpdate/stopLocationUpdates when lifecycle events fire. Set in setUpLifecycleObserver() (after init so we can capture self).
    private var locationLifecycleObserver: LocationLifecycleObserver?

    /// Use this initializer in tests to inject a location provider and coordinator (e.g. mocks).
    /// Production code creates the implementation via LocationModule.initialize() (invoked during CustomerIO.initialize(withConfig:)), which creates the provider on the main thread and injects it.
    /// Pass a no-op (e.g. NoOpAppLifecycleNotifying) in tests when lifecycle behavior is not under test.
    /// ApplicationStateProvider is injected into the lifecycle observer so it can trigger immediately when the app is already active (avoids missing the first didBecomeActive).
    init(
        config: LocationConfig,
        logger: Logger,
        locationProvider: any LocationProviding,
        locationSyncCoordinator: LocationSyncCoordinator,
        lifecycleNotifying: AppLifecycleNotifying,
        applicationStateProvider: ApplicationStateProvider
    ) {
        self.config = config
        self.logger = logger
        self.locationProvider = locationProvider
        self.locationSyncCoordinator = locationSyncCoordinator
        self.lifecycleNotifying = lifecycleNotifying
        self.applicationStateProvider = applicationStateProvider
        self.locationLifecycleObserver = nil
    }

    /// Creates and stores the lifecycle observer when mode is not `.off`. The observer registers for didBecomeActive first, then checks app state (register first, then check state) so the cold-start notification is not missed.
    func setUpLifecycleObserver() async {
        guard config.mode != .off else {
            locationLifecycleObserver = nil
            return
        }
        let observer = LocationLifecycleObserver(
            mode: config.mode,
            onBecomeActive: { [weak self] in
                self?.requestLocationUpdate()
            },
            onBackground: { [weak self] in
                self?.stopLocationUpdates()
            },
            lifecycleNotifying: lifecycleNotifying
        )
        locationLifecycleObserver = observer
        await observer.triggerIfAlreadyActive(applicationStateProvider: applicationStateProvider)
    }

    nonisolated func setLastKnownLocation(_ location: CLLocation) {
        pendingSetLastKnownLocationWork.mutating { pendingWork in
            let previousWork = pendingWork
            pendingWork = Task { [weak self] in
                await previousWork?.value
                await self?.setLastKnownLocationImpl(location)
            }
        }
    }

    /// Waits for location work that was enqueued before this method was called.
    /// Internal synchronization seam used by tests for the synchronous public API.
    nonisolated func waitForPendingSetLastKnownLocation() async {
        let pendingWork = pendingSetLastKnownLocationWork.using { $0 }
        await pendingWork?.value
    }

    nonisolated func requestLocationUpdate() {
        let requestEntryWork = Task { [weak self] in
            guard let self else { return }
            await self.startRequestIfNeeded(track: true, respectMode: true)
        }
        pendingLocationRequestEntryWork.wrappedValue = requestEntryWork
    }

    nonisolated func requestLocationUpdateSilently() {
        // Internal consumers (geofencing) need a fix regardless of the tracking mode, and it must
        // not emit a track event or be cached.
        let requestEntryWork = Task { [weak self] in
            guard let self else { return }
            await self.startRequestIfNeeded(track: false, respectMode: false)
        }
        pendingLocationRequestEntryWork.wrappedValue = requestEntryWork
    }

    nonisolated func getLastKnownLocation() async -> LocationData? {
        await locationSyncCoordinator.getLastKnownLocation()
    }

    /// Cancels any in-flight location request. No-op if nothing in progress. Called automatically when the app enters background; not exposed on the public LocationServices protocol.
    nonisolated func stopLocationUpdates() {
        let stopWork = Task { [weak self] in
            guard let self else { return }
            await self.stopLocationUpdatesImpl()
        }
        pendingStopLocationWork.wrappedValue = stopWork
    }

    /// Waits until the latest request has entered the actor and applied its request intent.
    /// This joins the latest assigned entry only. Overlap tests must first observe any earlier
    /// request in flight before releasing a held request.
    nonisolated func waitForPendingLocationRequestEntry() async {
        let requestEntryWork = pendingLocationRequestEntryWork.using { $0 }
        await requestEntryWork?.value
    }

    /// Waits for the latest request entry and any location acquisition it started or joined.
    /// Internal synchronization seam used by tests for the synchronous public API.
    nonisolated func waitForPendingLocationRequest() async {
        await waitForPendingLocationRequestEntry()
        await waitForCurrentLocationRequest()
    }

    /// Waits for the latest stop request to finish cancelling the provider.
    /// Internal synchronization seam used by tests for the synchronous public API.
    nonisolated func waitForPendingStopLocationUpdates() async {
        let stopWork = pendingStopLocationWork.using { $0 }
        await stopWork?.value
    }

    private func waitForCurrentLocationRequest() async {
        await currentTask?.value
    }

    private func stopLocationUpdatesImpl() async {
        if let task = currentTask {
            currentTask = nil
            task.cancel()
            _ = await task.value
        }
        await locationProvider.cancel()
    }

    private func setLastKnownLocationImpl(_ location: CLLocation) async {
        guard config.mode != .off else {
            logger.trackingDisabledIgnoringSetLastKnownLocation()
            return
        }

        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            logger.invalidCoordinates()
            return
        }

        logger.trackingLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        let locationData = LocationData(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        await locationSyncCoordinator.processLocationUpdate(locationData)
    }

    private func startRequestIfNeeded(track: Bool, respectMode: Bool) async {
        guard currentTask == nil else {
            // A dropped tracked request never retries this process (the lifecycle gate is
            // one-shot), so latch the intent instead; the `.off` gate is re-applied when
            // the in-flight request consumes it.
            if track { pendingTrackUpgrade = true }
            return
        }

        var task: Task<Void, Never>!
        task = Task { [weak self] in
            guard let self else { return }
            await self.runLocationRequest(track: track, respectMode: respectMode)
            await self.clearTaskIfCurrent(task)
        }
        currentTask = task
    }

    private func clearTaskIfCurrent(_ task: Task<Void, Never>) async {
        guard currentTask == task else { return }
        currentTask = nil
        // A tracked request can arrive after `runLocationRequest`'s `defer` cleared the latch but
        // while `currentTask` still looks busy. It is dropped either way; clearing here stops its
        // intent from being consumed by an unrelated later fix.
        pendingTrackUpgrade = false
    }

    /// - Parameters:
    ///   - track: whether a successful fix emits a `CIO Location Update` analytics event.
    ///   - respectMode: when true, honors the `.off` tracking mode (public path); geofence-initiated
    ///     fixes pass false so a location can be acquired even when location tracking is off.
    private func runLocationRequest(track: Bool, respectMode: Bool) async {
        // A latched upgrade that found no fix is dropped, matching what the tracked request
        // would have done itself (same provider, same failure; the gate retries neither).
        defer { pendingTrackUpgrade = false }
        if respectMode {
            guard config.mode != .off else {
                logger.trackingDisabledIgnoringRequestLocationUpdate()
                return
            }
        }
        if let result = await locationProvider.requestLocationOnce() {
            switch result {
            case .success(let snapshot):
                // The upgrade must not emit a track the public request itself would have
                // refused under `.off` (silent requests run regardless of mode).
                let upgraded = pendingTrackUpgrade && config.mode != .off
                await postLocation(snapshot, track: track || upgraded)
            case .failure(.cancelled):
                logger.locationRequestCancelled()
            case .failure(let error):
                logger.locationRequestFailed(error)
            }
        }
    }

    private func postLocation(_ snapshot: LocationSnapshot, track: Bool) async {
        logger.trackingLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let locationData = LocationData(latitude: snapshot.latitude, longitude: snapshot.longitude)
        await locationSyncCoordinator.processLocationUpdate(locationData, track: track)
    }
}
