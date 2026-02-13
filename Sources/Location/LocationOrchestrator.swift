import CioInternalCommon
import Foundation

/// Coordinates location requests: one-shot only. Uses injected LocationProviding (actor); callers use async API.
actor LocationOrchestrator {
    private let config: LocationConfig
    private let logger: Logger
    private let eventBusHandler: EventBusHandler
    private let locationProvider: any LocationProviding

    init(
        config: LocationConfig,
        logger: Logger,
        eventBusHandler: EventBusHandler,
        locationProvider: any LocationProviding
    ) {
        self.config = config
        self.logger = logger
        self.eventBusHandler = eventBusHandler
        self.locationProvider = locationProvider
    }

    /// Cancels any in-flight location request on the provider. Used by stopLocationUpdates().
    func cancelRequestLocation() async {
        await locationProvider.cancelRequestLocation()
    }

    func requestLocationUpdateOnce() async {
        guard config.enableLocationTracking else {
            logger.trackingDisabledIgnoringRequestLocationUpdateOnce()
            return
        }
        let auth = await locationProvider.currentAuthorizationStatus()
        guard auth.isAuthorized else {
            logger.locationPermissionNotGrantedIgnoringRequest()
            return
        }
        do {
            let snapshot = try await locationProvider.requestLocation(granularity: LocationGranularityDefaults.default)
            if Task.isCancelled {
                logger.locationRequestCancelled()
                return
            }
            postLocation(snapshot)
        } catch is CancellationError {
            logger.locationRequestCancelled()
        } catch {
            logger.locationRequestFailed(error)
        }
    }

    private func postLocation(_ snapshot: LocationSnapshot) {
        logger.trackingLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let locationData = LocationData(latitude: snapshot.latitude, longitude: snapshot.longitude)
        eventBusHandler.postEvent(TrackLocationEvent(location: locationData))
    }
}
