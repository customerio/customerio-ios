import CioInternalCommon
import CoreLocation
import Foundation

/// Single actor that owns CLLocationManager, permission state, and the one-shot continuation.
/// In-flight is represented by "continuation exists"; ignored calls return nil and are logged. No locks; delegate
/// callbacks re-enter the actor via Task { await self.finish(...) }.
///
/// Must be created on the main thread so CLLocationManager and delegate setup run on main.
actor CoreLocationProvider: NSObject, CLLocationManagerDelegate, LocationProviding {
    private let manager: CLLocationManager
    private let logger: Logger
    private var oneShotContinuation: CheckedContinuation<LocationResult, Never>?

    init(logger: Logger) {
        self.manager = CLLocationManager()
        self.logger = logger
        super.init()
        manager.delegate = self
    }

    func requestLocationOnce() async -> LocationResult? {
        guard oneShotContinuation == nil else {
            logger.locationRequestAlreadyInFlightIgnoringCall()
            return nil
        }

        let auth = await currentAuthorizationStatus()
        guard auth.isAuthorized else {
            return .failure(errorForUnauthorizedStatus(auth))
        }
        guard CLLocationManager.locationServicesEnabled() else {
            return .failure(.servicesDisabled)
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<LocationResult, Never>) in
                oneShotContinuation = cont
                let m = manager
                let accuracy = Self.accuracyForDefaultGranularity
                Task { @MainActor in
                    m.desiredAccuracy = accuracy
                    m.requestLocation()
                }
            }
        } onCancel: {
            Task { await cancel() }
        }
    }

    func cancel() async {
        if let cont = oneShotContinuation {
            oneShotContinuation = nil
            cont.resume(returning: .failure(.cancelled))
        }
    }

    // MARK: - CLLocationManagerDelegate (nonisolated; re-enter actor via Task)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { await self.finishWithLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { await self.finishWithError(error) }
    }

    // MARK: - Private (actor-isolated)

    private func currentAuthorizationStatus() async -> AuthorizationSnapshot {
        let m = manager
        let clStatus: CLAuthorizationStatus = await MainActor.run {
            if #available(iOS 14.0, *) {
                return m.authorizationStatus
            } else {
                return CLLocationManager.authorizationStatus()
            }
        }
        return AuthorizationSnapshot(status: authorizationStatusFromCL(clStatus))
    }

    private func finishWithLocation(_ location: CLLocation?) {
        guard let location else {
            finish(.failure(.timeout))
            return
        }
        finish(.success(snapshot(from: location)))
    }

    private func finishWithError(_ error: Error) {
        let providerError: LocationProviderError = if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                .permissionDenied
            case .locationUnknown, .network:
                .timeout
            default:
                .timeout
            }
        } else {
            .timeout
        }
        finish(.failure(providerError))
    }

    private func finish(_ result: LocationResult) {
        guard let cont = oneShotContinuation else { return }
        oneShotContinuation = nil
        cont.resume(returning: result)
    }

    private func snapshot(from location: CLLocation) -> LocationSnapshot {
        LocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude
        )
    }

    private func authorizationStatusFromCL(_ status: CLAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways: .authorizedAlways
        case .authorizedWhenInUse: .authorizedWhenInUse
        @unknown default: .notDetermined
        }
    }

    private func errorForUnauthorizedStatus(_ snapshot: AuthorizationSnapshot) -> LocationProviderError {
        switch snapshot.status {
        case .notDetermined: .permissionNotDetermined
        case .restricted, .denied, .authorizedAlways, .authorizedWhenInUse: .permissionDenied
        @unknown default: .permissionDenied
        }
    }

    private static var accuracyForDefaultGranularity: CLLocationAccuracy { 10000 }
}
