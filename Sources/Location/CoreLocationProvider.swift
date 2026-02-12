import CoreLocation
import Foundation

/// Wraps CLLocationManager; all location-manager logic lives here.
/// Receives manager and proxy via injection; the caller must create them on the main thread.
/// All manager access is confined to MainActor.run. Staleness / deduplication is handled later (M3 LocationFilter), not here.
actor CoreLocationProvider: LocationProviding {
    private nonisolated let manager: CLLocationManager
    private nonisolated let proxy: CoreLocationProviderDelegateProxy
    private var oneShotContinuation: CheckedContinuation<LocationSnapshot, Error>?
    /// Zero when no request; non-zero while a request is in flight. Cleared on cancel/complete.
    private var oneShotGeneration: Int = 0

    /// Injected dependencies; manager and proxy must be created on the main thread by the caller.
    init(manager: CLLocationManager, proxy: CoreLocationProviderDelegateProxy) {
        self.manager = manager
        self.proxy = proxy
    }

    func requestLocation(granularity: LocationGranularity) async throws -> LocationSnapshot {
        clearOneShotState()
        oneShotGeneration = 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                oneShotContinuation = continuation
                Task {
                    let auth = await currentAuthorizationStatus()
                    guard auth.isAuthorized else {
                        completeOneShot(.failure(errorForUnauthorizedStatus(auth)))
                        return
                    }
                    guard CLLocationManager.locationServicesEnabled() else {
                        completeOneShot(.failure(.servicesDisabled))
                        return
                    }
                    if Task.isCancelled {
                        completeOneShot(throwing: CancellationError())
                        return
                    }
                    let m = manager
                    let accuracy = Self.accuracy(for: granularity)
                    Task { @MainActor in
                        m.desiredAccuracy = accuracy
                        m.requestLocation()
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelRequestLocation() }
        }
    }

    func cancelRequestLocation() async {
        oneShotContinuation?.resume(throwing: CancellationError())
        oneShotContinuation = nil
        oneShotGeneration = 0
        // We do not remove manager.delegate. CLLocationManager may still invoke the delegate once
        // (didUpdateLocations or didFailWithError) after cancel; the handlers below no-op when
        // oneShotContinuation is nil, so no double-resume and no update is delivered.
    }

    func currentAuthorizationStatus() async -> AuthorizationSnapshot {
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

    // MARK: - Delegate entry points (called from proxy via Task)

    // If the request was cancelled, oneShotContinuation is nil; we no-op so late callbacks are ignored.

    func didUpdateLocations(_ locations: [CLLocation]) async {
        guard let location = locations.last else { return }
        completeOneShot(.success(snapshot(from: location)))
    }

    func didFailWithError(_ error: Error) async {
        let providerError: LocationProviderError = if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                errorForUnauthorizedStatus(await currentAuthorizationStatus())
            case .locationUnknown:
                .timeout
            case .network:
                .timeout
            default:
                .timeout
            }
        } else {
            .timeout
        }
        completeOneShot(.failure(providerError))
    }

    // MARK: - Private

    private func clearOneShotState() {
        oneShotContinuation?.resume(throwing: CancellationError())
        oneShotContinuation = nil
        oneShotGeneration = 0
    }

    private func completeOneShot(_ result: Result<LocationSnapshot, LocationProviderError>) {
        guard let cont = oneShotContinuation else { return }
        oneShotContinuation = nil
        oneShotGeneration = 0
        switch result {
        case .success(let snapshot):
            cont.resume(returning: snapshot)
        case .failure(let error):
            cont.resume(throwing: error)
        }
    }

    /// Completes the one-shot with an arbitrary error (e.g. CancellationError). Used when the task is cancelled before starting CLLocationManager.requestLocation().
    private func completeOneShot(throwing error: Error) {
        guard let cont = oneShotContinuation else { return }
        oneShotContinuation = nil
        oneShotGeneration = 0
        cont.resume(throwing: error)
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

    /// Maps unauthorized authorization state to a provider error. Use only when status is not authorized.
    private func errorForUnauthorizedStatus(_ snapshot: AuthorizationSnapshot) -> LocationProviderError {
        switch snapshot.status {
        case .notDetermined:
            .permissionNotDetermined
        case .restricted, .denied:
            .permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            .permissionDenied
        @unknown default:
            .permissionDenied
        }
    }

    private static func accuracy(for granularity: LocationGranularity) -> CLLocationAccuracy {
        switch granularity {
        case .coarseCityOrTimezone:
            // Coarser than kCLLocationAccuracyThreeKilometers (3 km). 10 km is more appropriate for city/timezone.
            return 10000
        }
    }
}
