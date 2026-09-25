import CioInternalCommon
import CoreLocation
import Foundation

/// Ensures the fix attached to a movement-trigger EXIT is fresh before it drives a sync pass.
///
/// Which decision asked for a fix. One resolver serves five call sites, so without this every
/// `movement.fix.resolved` record joins one population — and the wake margin is calibrated from
/// the movement one alone. No default: a new call site must say which it is, or it silently
/// contaminates the sample.
enum GeofenceFixPurpose: String, CaseIterable {
    case movement
    case contradictionGate = "gate"
    case baselineHeal = "heal"
    case pendingEvents = "pending"
    case polygon
}

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
    /// Freshness is measured against this clock, never the wall clock.
    private let dateUtil: DateUtil
    private let desiredAccuracy: CLLocationAccuracy

    /// Created lazily so tests using the `requestFreshFix` seam never touch CoreLocation.
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.desiredAccuracy = desiredAccuracy
        manager.delegate = self
        return manager
    }()

    /// Test seam mirroring `requestFreshFix`: where the pre-request fix comes from when this
    /// resolver has delivered none itself. Unset, it reads CoreLocation's own cached fix — so any
    /// test that reads `cachedFix` must set this, or the read instantiates a real
    /// `CLLocationManager`. A seam returning nil answers nil; it does not fall through.
    var systemCachedFix: (() -> CLLocation?)?

    /// Freshest usable fix obtainable without issuing a request: the newer of the two sources, not
    /// whichever this resolver happens to have produced, which is how the monitors' `bestKnownFix`
    /// reads too. On a cold process this resolver has delivered nothing, so CoreLocation's cached
    /// fix is the only evidence available, and the decision's age gate is what keeps it honest.
    /// That cache also moves on its own between passes, driven by other clients in the process, so
    /// preferring `latestFix` by source would hand a stale fallback to a request that then fails.
    ///
    /// Only the system fix is checked for a valid coordinate. `latestFix` reaches this class
    /// through a delegate callback that already rejects invalid ones — which a test feeding
    /// `handleResolvedFix` directly does not.
    ///
    /// This is a FALLBACK VALUE — the best position to act on when no request is made — and newest
    /// is what makes it best. It is not a freshness baseline: a caller asking "is the answer newer
    /// than what I had" must compare against `latestFix`, because this property tracks a cache that
    /// advances on its own and would leave nothing able to beat it.
    var cachedFix: CLLocation? {
        FixSelection.newest(
            cached: FixSelection.usable(systemCachedFix.map { $0() } ?? manager.location),
            delivered: latestFix
        )?.fix
    }

    /// Freshest fix this resolver has received, retained even when it arrives after a timeout.
    private(set) var latestFix: CLLocation?
    private var pendingCompletions: [(LocationData?, Bool) -> Void] = []
    /// Newest cached fix seen while a request is in flight — the fallback on failure/timeout.
    private var fallbackFix: CLLocation?
    /// Purpose of the caller that started the in-flight request; see `resolve`.
    private var pendingPurpose: GeofenceFixPurpose?
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

    /// How the timeout waits. The OS clock is the default; a caller driving a recorded timeline
    /// supplies its own so the wait costs what the timeline says rather than real seconds.
    ///
    /// Settable rather than init-only, for the same reason as `requestFreshFix`: this resolver is
    /// constructed inside `CLMonitorGeofenceMonitor`, so a caller has no way to reach the
    /// initialiser. Without it the fallback fires ten real seconds after a replay that finished in
    /// milliseconds of virtual time — long after the run it belonged to.
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

    /// Completes with a fix no older than `maxAge` when one can be obtained, exactly once per call.
    /// `cached` should be the caller's best currently-known fix.
    ///
    /// The completion's `Bool` is whether those coordinates are current: true for a delivered fix or
    /// a cached one still inside `maxAge`, false when the request failed or timed out and the answer
    /// is `fallbackFix` — which is by definition the stale fix that prompted the request. A caller
    /// that sizes anything to the coordinates needs that apart, and deriving it from the fix's age
    /// at the call site would put this rule in two more places to get wrong.
    func resolve(cached: CLLocation?, purpose: GeofenceFixPurpose, completion: @escaping (LocationData?, Bool) -> Void) {
        let age = cached.map { self.age(of: $0) }
        if let cached, let age, age <= maxAge {
            logger.geofenceMovementFixResolved(ageSeconds: age, requested: false, speed: cached.speed, purpose: purpose)
            completion(locationData(from: cached), true)
            return
        }
        logger.geofenceMovementFixStale(ageSeconds: age)
        // Same newest-of-two rule, and the same tie (the held fallback keeps it); provenance is
        // not tracked here because this value never reaches a diagnostic.
        fallbackFix = FixSelection.newest(cached: cached, delivered: fallbackFix)?.fix
        pendingCompletions.append(completion)
        guard pendingCompletions.count == 1 else { return }
        // The initiator labels the record. Later callers coalesce onto this request and return
        // through `completeAll` without logging, so one request still yields exactly one record.
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

    /// One fix from the OS, freshness not yet judged: a new manager can echo a stale cached location.
    func handleDeliveredFix(_ fix: CLLocation) {
        guard age(of: fix) <= maxAge else {
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

    private func recordDeliveredFix(_ fix: CLLocation) {
        logger.geofenceFixReceived(fix, source: "movement_resolver", now: dateUtil.now)
        if latestFix.map({ fix.timestamp > $0.timestamp }) ?? true {
            latestFix = fix
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
