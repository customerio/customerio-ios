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
    /// Only one request at a time; calling again cancels any in-flight request and starts a new one.
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

final class LocationServicesImplementation: LocationServices {
    private let config: LocationConfig
    private let logger: Logger
    private let eventBusHandler: EventBusHandler
    private let orchestrator: LocationOrchestrator
    private let taskLock = NSLock()
    private var currentLocationTask: Task<Void, Never>?

    /// Use this initializer in tests to inject a location provider (e.g. mock).
    /// Production code creates the implementation via CustomerIO.initializeLocation(withConfig:), which creates the provider on the main thread and injects it.
    init(config: LocationConfig, logger: Logger, eventBusHandler: EventBusHandler, locationProvider: any LocationProviding) {
        self.config = config
        self.logger = logger
        self.eventBusHandler = eventBusHandler
        self.orchestrator = LocationOrchestrator(
            config: config,
            logger: logger,
            eventBusHandler: eventBusHandler,
            locationProvider: locationProvider
        )
    }

    func setLastKnownLocation(_ location: CLLocation) {
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

    func requestLocationUpdateOnce() {
        taskLock.lock()
        let previousTask = currentLocationTask
        let orch = orchestrator
        var newTask: Task<Void, Never>!
        newTask = Task {
            defer {
                taskLock.lock()
                if currentLocationTask == newTask {
                    currentLocationTask = nil
                }
                taskLock.unlock()
            }
            if let prev = previousTask {
                prev.cancel()
                _ = await prev.result
            }
            await orch.requestLocationUpdateOnce()
        }
        currentLocationTask = newTask
        taskLock.unlock()
    }

    func stopLocationUpdates() async {
        taskLock.lock()
        let task = currentLocationTask
        currentLocationTask = nil
        let orchestrator = orchestrator
        taskLock.unlock()
        task?.cancel()
        _ = await task?.result
        await orchestrator.cancelRequestLocation()
    }
}
