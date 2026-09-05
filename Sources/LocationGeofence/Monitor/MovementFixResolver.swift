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
    private let backgroundTaskRunner: BackgroundTaskRunner

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
    /// Monotonic start of the in-flight request, so a failure can report how long it waited —
    /// "timed out after 10s" and "failed immediately" are different faults.
    private var requestStartedAt: TimeInterval?
    /// Completed when the in-flight request resolves, releasing its background-time window.
    /// One signal per request cycle, so a window can never outlive its own cycle.
    private var currentRequestSignal: RequestCompletionSignal?

    /// Test seam: replaces the manager's one-shot request. Tests inject this and then feed
    /// `handleResolvedFix` / `handleRequestFailure` directly.
    var requestFreshFix: (() -> Void)?

    init(
        logger: Logger,
        maxAge: TimeInterval = GeofenceConstants.movementFixMaxAge,
        requestTimeout: TimeInterval = GeofenceConstants.movementFixRequestTimeout,
        backgroundTaskRunner: BackgroundTaskRunner = NoBackgroundTaskRunner()
    ) {
        self.logger = logger
        self.maxAge = maxAge
        self.requestTimeout = requestTimeout
        self.backgroundTaskRunner = backgroundTaskRunner
    }

    deinit {
        timeoutTask?.cancel()
        currentRequestSignal?.complete()
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
        requestStartedAt = GeofenceLog.monotonicNow()
        startTimeout()
        holdBackgroundTimeUntilCompletion()
        if let requestFreshFix {
            requestFreshFix()
        } else {
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, CLLocationCoordinate2DIsValid(fix.coordinate),
              fix.horizontalAccuracy > 0
        else { return }
        // Core Location can echo a cached location as a new manager's first delivery. A fix as
        // stale as the one that prompted the request must not complete the pass as "fresh" —
        // keep waiting; the timeout falls back if nothing recent arrives.
        guard -fix.timestamp.timeIntervalSinceNow <= maxAge else {
            recordDeliveredFix(fix)
            return
        }
        handleResolvedFix(fix)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handleRequestFailure()
    }

    // MARK: - Internal (also the test seam's feed points)

    func handleResolvedFix(_ fix: CLLocation) {
        recordDeliveredFix(fix)
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixResolved(ageSeconds: -fix.timestamp.timeIntervalSinceNow, requested: true)
        completeAll(with: locationData(from: fix))
    }

    func handleRequestFailure() {
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixRequestFailed(
            fallingBackToCached: fallbackFix != nil,
            elapsed: requestStartedAt.map { GeofenceLog.monotonicNow() - $0 }
        )
        completeAll(with: fallbackFix.map(locationData(from:)))
    }

    // MARK: - Private

    private func recordDeliveredFix(_ fix: CLLocation) {
        logger.geofenceFixReceived(fix, source: "movement_resolver")
        if latestFix.map({ fix.timestamp > $0.timestamp }) ?? true {
            latestFix = fix
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self, requestTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(requestTimeout * 1000000000))
            guard !Task.isCancelled else { return }
            self?.handleRequestFailure()
        }
    }

    /// A region wake grants only a short execution window, and the request may consume most of it
    /// before the movement pass even starts. Holding a background-task assertion for the life of
    /// the request keeps the no-drop guarantee from depending on the wake window's leftovers.
    private func holdBackgroundTimeUntilCompletion() {
        let signal = RequestCompletionSignal()
        currentRequestSignal = signal
        let runner = backgroundTaskRunner
        Task {
            await runner.withBackgroundTime { await signal.wait() }
        }
    }

    private func completeAll(with location: LocationData?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        fallbackFix = nil
        requestStartedAt = nil
        currentRequestSignal?.complete()
        currentRequestSignal = nil
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

/// Awaitable one-shot completion flag. `wait()` returns when `complete()` has been called,
/// regardless of order; both are safe from any thread and idempotent.
private final class RequestCompletionSignal: Sendable {
    private struct State {
        var isCompleted = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = Synchronized<State>(State())

    func complete() {
        let continuation = state.mutating { state -> CheckedContinuation<Void, Never>? in
            state.isCompleted = true
            let pending = state.continuation
            state.continuation = nil
            return pending
        }
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.mutating { state -> Bool in
                if state.isCompleted { return true }
                state.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}
