import CioInternalCommon
import CoreLocation
import Foundation

// MARK: - LocationServices

/// Protocol for the Location module's public API.
///
/// Use `CustomerIO.location` after calling `CustomerIO.initializeLocation(withConfig:)`
/// to get the instance.
///
/// **Example:**
/// ```swift
/// CustomerIO.initializeLocation(withConfig: LocationConfig(enableLocationTracking: true))
/// CustomerIO.location.setLastKnownLocation(clLocation)
/// CustomerIO.location.requestLocationUpdateOnce()
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
    /// Only one request at a time; further calls are ignored while a request is already in progress.
    ///
    /// The SDK does not request location permission. The host app must prompt for authorization
    /// (e.g. via `CLLocationManager.requestWhenInUseAuthorization()`) and only call this when permission is granted.
    func requestLocationUpdateOnce()

    /// Cancels any in-flight location request. No-op if nothing in progress. Call from an async context (e.g. `await location.stopLocationUpdates()`).
    func stopLocationUpdates() async
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

    func requestLocationUpdateOnce() {
        logger.moduleNotInitialized()
    }

    func stopLocationUpdates() async {
        logger.moduleNotInitialized()
    }
}

// MARK: - LocationServicesImplementation (internal, real implementation)

actor LocationServicesImplementation: LocationServices {
    private let config: LocationConfig
    private let logger: Logger
    private let eventBusHandler: EventBusHandler
    private let locationProvider: any LocationProviding
    private var currentTask: Task<Void, Never>?

    /// Use this initializer in tests to inject a location provider (e.g. mock).
    /// Production code creates the implementation via CustomerIO.initializeLocation(withConfig:), which creates the provider on the main thread and injects it.
    init(config: LocationConfig, logger: Logger, eventBusHandler: EventBusHandler, locationProvider: any LocationProviding) {
        self.config = config
        self.logger = logger
        self.eventBusHandler = eventBusHandler
        self.locationProvider = locationProvider
    }

    nonisolated func setLastKnownLocation(_ location: CLLocation) {
        Task { await self.setLastKnownLocationImpl(location) }
    }

    nonisolated func requestLocationUpdateOnce() {
        Task { await self.startRequestIfNeeded() }
    }

    func stopLocationUpdates() async {
        if let task = currentTask {
            currentTask = nil
            task.cancel()
            _ = await task.value
        }
        await locationProvider.cancel()
    }

    private func setLastKnownLocationImpl(_ location: CLLocation) async {
        guard config.enableLocationTracking else {
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

        let event = TrackLocationEvent(location: locationData)
        eventBusHandler.postEvent(event)
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
        guard config.enableLocationTracking else {
            logger.trackingDisabledIgnoringRequestLocationUpdateOnce()
            return
        }
        if let result = await locationProvider.requestLocationOnce() {
            switch result {
            case .success(let snapshot):
                postLocation(snapshot)
            case .failure(.cancelled):
                logger.locationRequestCancelled()
            case .failure(let error):
                logger.locationRequestFailed(error)
            }
        }
    }

    private func postLocation(_ snapshot: LocationSnapshot) {
        logger.trackingLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let locationData = LocationData(latitude: snapshot.latitude, longitude: snapshot.longitude)
        eventBusHandler.postEvent(TrackLocationEvent(location: locationData))
    }
}
