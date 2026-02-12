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
}

// MARK: - LocationServicesImplementation (internal, real implementation)

final class LocationServicesImplementation: LocationServices {
    private let config: LocationConfig
    private let logger: Logger
    private let eventBusHandler: EventBusHandler

    init(config: LocationConfig, logger: Logger, eventBusHandler: EventBusHandler) {
        self.config = config
        self.logger = logger
        self.eventBusHandler = eventBusHandler
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
}
