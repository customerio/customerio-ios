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
}

// MARK: - LocationServicesImplementation (internal, real implementation)

actor LocationServicesImplementation: LocationServices {
    private let config: LocationConfig
    private let logger: Logger
    private let locationProvider: any LocationProviding
    private let locationSyncCoordinator: LocationSyncCoordinator
    private let lifecycleNotifying: AppLifecycleNotifying
    private let applicationStateProvider: ApplicationStateProvider
    private var currentTask: Task<Void, Never>?
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
        Task { await self.setLastKnownLocationImpl(location) }
    }

    nonisolated func requestLocationUpdate() {
        Task { await self.startRequestIfNeeded() }
    }

    /// Cancels any in-flight location request. No-op if nothing in progress. Called automatically when the app enters background; not exposed on the public LocationServices protocol.
    nonisolated func stopLocationUpdates() {
        Task { await self.stopLocationUpdatesImpl() }
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

    private func startRequestIfNeeded() async {
        guard currentTask == nil else { return }

        var task: Task<Void, Never>!
        task = Task { [weak self] in
            guard let self else { return }
            await self.runLocationRequest()
            await self.clearTaskIfCurrent(task)
        }
        currentTask = task
    }

    private func clearTaskIfCurrent(_ task: Task<Void, Never>) async {
        if currentTask == task { currentTask = nil }
    }

    private func runLocationRequest() async {
        guard config.mode != .off else {
            logger.trackingDisabledIgnoringRequestLocationUpdate()
            return
        }
        if let result = await locationProvider.requestLocationOnce() {
            switch result {
            case .success(let snapshot):
                await postLocation(snapshot)
            case .failure(.cancelled):
                logger.locationRequestCancelled()
            case .failure(let error):
                logger.locationRequestFailed(error)
            }
        }
    }

    private func postLocation(_ snapshot: LocationSnapshot) async {
        logger.trackingLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let locationData = LocationData(latitude: snapshot.latitude, longitude: snapshot.longitude)
        await locationSyncCoordinator.processLocationUpdate(locationData)
    }
}
