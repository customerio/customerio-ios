import CioInternalCommon
import CoreLocation
import Foundation

/// Ensures the fix attached to a movement-trigger EXIT is fresh before it drives a sync pass.
///
/// `CLLocationManager.location` on a long-suspended process can stay frozen at the fix cached
/// around process start, anchoring every movement pass (re-rank point, trigger re-center, the
/// moved-beyond check) to a stale position for a whole trip. A cached fix older than
/// `GeofenceConstants.movementFixMaxAge` triggers a one-shot request; on failure or after
/// `movementFixRequestTimeout` the pass falls back to the cached fix, so it is never worse off
/// than without the resolver. Concurrent resolutions coalesce onto one in-flight request, and
/// `latestFix` retains the freshest delivered fix for the monitor's other cached-fix reads.
///
/// Owns its manager instead of routing through the Location module's provider: on a wrapper cold
/// wake `CustomerIO.initialize` has not run, and movement passes must work in exactly that state.
@MainActor
final class MovementFixResolver: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let logger: Logger
    private let maxAge: TimeInterval
    private let requestTimeout: TimeInterval

    /// Created lazily so tests using the `requestFreshFix` seam never touch CoreLocation.
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        return manager
    }()

    /// Freshest fix this resolver has received, retained even when it arrives after a timeout.
    private(set) var latestFix: CLLocation?
    private var pendingCompletions: [(LocationData?) -> Void] = []
    /// Newest cached fix seen while a request is in flight — the fallback on failure/timeout.
    private var fallbackFix: CLLocation?
    private var timeoutTask: Task<Void, Never>?

    /// Test seam: replaces the manager's one-shot request. Tests inject this and then feed
    /// `handleResolvedFix` / `handleRequestFailure` directly.
    var requestFreshFix: (() -> Void)?

    init(
        logger: Logger,
        maxAge: TimeInterval = GeofenceConstants.movementFixMaxAge,
        requestTimeout: TimeInterval = GeofenceConstants.movementFixRequestTimeout
    ) {
        self.logger = logger
        self.maxAge = maxAge
        self.requestTimeout = requestTimeout
    }

    deinit {
        timeoutTask?.cancel()
    }

    /// Completes with a fix no older than `maxAge` when one can be obtained, exactly once per call.
    /// `cached` should be the caller's best currently-known fix.
    func resolve(cached: CLLocation?, completion: @escaping (LocationData?) -> Void) {
        let age = cached.map { -$0.timestamp.timeIntervalSinceNow }
        if let cached, let age, age <= maxAge {
            logger.geofenceMovementFixResolved(ageSeconds: age, requested: false)
            completion(locationData(from: cached))
            return
        }
        logger.geofenceMovementFixStale(ageSeconds: age)
        if let cached, fallbackFix.map({ cached.timestamp > $0.timestamp }) ?? true {
            fallbackFix = cached
        }
        pendingCompletions.append(completion)
        guard pendingCompletions.count == 1 else { return }
        startTimeout()
        if let requestFreshFix {
            requestFreshFix()
        } else {
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
        handleResolvedFix(fix)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handleRequestFailure()
    }

    // MARK: - Internal (also the test seam's feed points)

    func handleResolvedFix(_ fix: CLLocation) {
        if latestFix.map({ fix.timestamp > $0.timestamp }) ?? true {
            latestFix = fix
        }
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixResolved(ageSeconds: -fix.timestamp.timeIntervalSinceNow, requested: true)
        completeAll(with: locationData(from: fix))
    }

    func handleRequestFailure() {
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixRequestFailed(fallingBackToCached: fallbackFix != nil)
        completeAll(with: fallbackFix.map(locationData(from:)))
    }

    // MARK: - Private

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self, requestTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(requestTimeout * 1000000000))
            guard !Task.isCancelled else { return }
            self?.handleRequestFailure()
        }
    }

    private func completeAll(with location: LocationData?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        fallbackFix = nil
        let completions = pendingCompletions
        pendingCompletions = []
        for completion in completions {
            completion(location)
        }
    }

    private func locationData(from fix: CLLocation) -> LocationData {
        LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }
}
