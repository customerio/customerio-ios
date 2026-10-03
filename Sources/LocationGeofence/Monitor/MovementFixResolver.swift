import CioInternalCommon
import CoreLocation
import Foundation

/// The wake margin is calibrated from `movement` records alone, so a new call site needs its own case.
enum GeofenceFixPurpose: String, CaseIterable {
    case movement
    case contradictionGate = "gate"
    case baselineHeal = "heal"
    case pendingEvents = "pending"
    case polygon
}

/// Owns its manager rather than using the Location module's provider: movement passes must work on
/// a wrapper cold wake, before `CustomerIO.initialize` has run.
@MainActor
final class MovementFixResolver: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let logger: Logger
    private let maxAge: TimeInterval
    private let requestTimeout: TimeInterval
    private let backgroundTaskRunner: BackgroundTaskRunner
    /// Freshness is measured against this clock, never the wall clock.
    private let dateUtil: DateUtil
    private let desiredAccuracy: CLLocationAccuracy

    /// Lazy so tests using the `requestFreshFix` seam never touch CoreLocation.
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.desiredAccuracy = desiredAccuracy
        manager.delegate = self
        return manager
    }()

    /// Test seam. A test reading `cachedFix` must set it, or the read creates a real
    /// `CLLocationManager`. Returning nil answers nil; it doesn't fall through.
    var systemCachedFix: (() -> CLLocation?)?

    /// The newer of the OS cache and `latestFix`, since the cache moves on its own. A fallback, not a
    /// freshness baseline: compare against `latestFix` for "is the answer newer". A fix dated in the
    /// future of the clock is neither.
    var cachedFix: CLLocation? {
        FixSelection.newest(
            cached: FixSelection.usable(systemCachedFix.map { $0() } ?? manager.location).flatMap { isFuture($0) ? nil : $0 },
            delivered: latestFix
        )?.fix
    }

    /// Retained even when it arrives after a timeout. Hidden once it reads as from the future —
    /// delivered before the clock was set back — so it can neither pass as fresh nor outrank a fix
    /// taken on the current clock.
    var latestFix: CLLocation? {
        deliveredFix.flatMap { isFuture($0) ? nil : $0 }
    }

    private var deliveredFix: CLLocation?
    private var pendingCompletions: [(LocationData?, Bool) -> Void] = []
    private var fallbackFix: CLLocation?
    private var pendingPurpose: GeofenceFixPurpose?
    private var timeoutTask: Task<Void, Never>?
    private var requestStartedAt: TimeInterval?
    /// One per request cycle, so a background-time window can't outlive its cycle.
    private var currentRequestSignal: RequestCompletionSignal?

    /// Test seam replacing the one-shot request.
    var requestFreshFix: (() -> Void)?

    /// Settable because the monitors construct this resolver, so a caller can't reach `init`.
    var waitForTimeout: (TimeInterval) async -> Void

    init(
        logger: Logger,
        maxAge: TimeInterval = GeofenceConstants.movementFixMaxAge,
        requestTimeout: TimeInterval = GeofenceConstants.movementFixRequestTimeout,
        backgroundTaskRunner: BackgroundTaskRunner = NoBackgroundTaskRunner(),
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil,
        desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters,
        waitForTimeout: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
        }
    ) {
        self.logger = logger
        self.maxAge = maxAge
        self.requestTimeout = requestTimeout
        self.backgroundTaskRunner = backgroundTaskRunner
        self.dateUtil = dateUtil
        self.waitForTimeout = waitForTimeout
        self.desiredAccuracy = desiredAccuracy
    }

    deinit {
        timeoutTask?.cancel()
        currentRequestSignal?.complete()
    }

    /// Completes exactly once per call. The `Bool` is whether the coordinates are current: false when
    /// the request failed or timed out and the answer is the stale fallback.
    func resolve(cached: CLLocation?, purpose: GeofenceFixPurpose, completion: @escaping (LocationData?, Bool) -> Void) {
        let age = cached.map { self.age(of: $0) }
        if let cached, let age, isCurrent(cached) {
            logger.geofenceMovementFixResolved(ageSeconds: age, requested: false, speed: cached.speed, purpose: purpose)
            completion(locationData(from: cached), true)
            return
        }
        logger.geofenceMovementFixStale(ageSeconds: age)
        // On a tie the held fallback wins.
        fallbackFix = FixSelection.newest(cached: cached, delivered: fallbackFix)?.fix
        pendingCompletions.append(completion)
        guard pendingCompletions.count == 1 else { return }
        // The initiator labels the record; coalesced callers don't log, so one request, one record.
        pendingPurpose = purpose
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
        handleDeliveredFix(fix)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handleRequestFailure()
    }

    // MARK: - Internal (also the test seam's feed points)

    /// Freshness not yet judged: a new manager can echo a stale cached location.
    func handleDeliveredFix(_ fix: CLLocation) {
        guard isCurrent(fix) else {
            recordDeliveredFix(fix)
            return
        }
        handleResolvedFix(fix)
    }

    func handleResolvedFix(_ fix: CLLocation) {
        recordDeliveredFix(fix)
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixResolved(ageSeconds: age(of: fix), requested: true, speed: fix.speed, purpose: pendingPurpose)
        completeAll(with: locationData(from: fix), isFresh: true)
    }

    func handleRequestFailure() {
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixRequestFailed(
            fallingBackToCached: fallbackFix != nil,
            elapsed: requestStartedAt.map { GeofenceLog.monotonicNow() - $0 }
        )
        completeAll(with: fallbackFix.map(locationData(from:)), isFresh: false)
    }

    // MARK: - Private

    private func age(of fix: CLLocation) -> TimeInterval {
        dateUtil.now.timeIntervalSince(fix.timestamp)
    }

    /// Fresh: no older than `maxAge`, and not from the future. A future date means the fix was taken
    /// before the clock was set back, at a time the current clock cannot place. A second of slack
    /// absorbs read skew between the fix's clock and this one.
    private func isCurrent(_ fix: CLLocation) -> Bool {
        let age = age(of: fix)
        return age >= -GeofenceConstants.dwellWallClockStepTolerance && age <= maxAge
    }

    private func isFuture(_ fix: CLLocation) -> Bool {
        age(of: fix) < -GeofenceConstants.dwellWallClockStepTolerance
    }

    private func recordDeliveredFix(_ fix: CLLocation) {
        logger.geofenceFixReceived(fix, source: "movement_resolver", now: dateUtil.now)
        guard !isFuture(fix) else { return }
        if latestFix.map({ fix.timestamp > $0.timestamp }) ?? true {
            deliveredFix = fix
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self, requestTimeout, waitForTimeout] in
            await waitForTimeout(requestTimeout)
            guard !Task.isCancelled else { return }
            self?.handleRequestFailure()
        }
    }

    /// A region wake's short window may be mostly spent on the request, so hold background time for
    /// the request's life.
    private func holdBackgroundTimeUntilCompletion() {
        let signal = RequestCompletionSignal()
        currentRequestSignal = signal
        let runner = backgroundTaskRunner
        Task {
            await runner.withBackgroundTime { await signal.wait() }
        }
    }

    private func completeAll(with location: LocationData?, isFresh: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        fallbackFix = nil
        requestStartedAt = nil
        pendingPurpose = nil
        currentRequestSignal?.complete()
        currentRequestSignal = nil
        let completions = pendingCompletions
        pendingCompletions = []
        for completion in completions {
            completion(location, isFresh)
        }
    }

    private func locationData(from fix: CLLocation) -> LocationData {
        LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }
}

/// `wait()` returns once `complete()` has been called, in either order; both are thread-safe and
/// idempotent.
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
