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
    /// Callers waiting on the request in flight, the one that issued it included.
    var waitingCallers: Int { pendingCompletions.count }
    /// Test seam, nil in production: called as a caller starts waiting on a request; the closure it
    /// returns runs as that caller's completion is delivered.
    var onCallerWaiting: (() -> () -> Void)?
    private var fallbackFix: CLLocation?
    private var pendingPurpose: GeofenceFixPurpose?
    private var timeoutTask: Task<Void, Never>?
    private var requestStartedAt: TimeInterval?
    /// One per request cycle, so a background-time window can't outlive its cycle.
    private var currentRequestSignal: RequestCompletionSignal?

    /// Test seam replacing the one-shot request.
    var requestFreshFix: (() -> Void)?
    /// Test seam replacing the request's cancellation, used with `requestFreshFix`.
    var cancelFreshFix: (() -> Void)?

    /// Settable because the monitors construct this resolver, so a caller can't reach `init`.
    var waitForTimeout: (TimeInterval) async -> Void
    /// Starts the timeout, which is what delivers a fire-and-forget caller's completion.
    private let taskSpawner: GeofenceTaskSpawning

    /// Opt-in dwell diagnostics; nil records nothing. It only observes: no fix qualification,
    /// coalescing or timeout reads it.
    private let diagnosticRecorder: DwellDiagnosticRecorder?
    /// The diagnostics generation the latest request cycle began in, captured before it asked. Its
    /// answers, late ones too, record under it, so after a reset they are dropped rather than joining
    /// the next identity's history. Nil until a cycle has run: a fix nobody asked for records nothing.
    private var cycleDiagnosticToken: UInt64?

    init(
        logger: Logger,
        maxAge: TimeInterval = GeofenceConstants.movementFixMaxAge,
        requestTimeout: TimeInterval = GeofenceConstants.movementFixRequestTimeout,
        backgroundTaskRunner: BackgroundTaskRunner = NoBackgroundTaskRunner(),
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil,
        desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters,
        diagnosticRecorder: DwellDiagnosticRecorder? = nil,
        waitForTimeout: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
        },
        taskSpawner: GeofenceTaskSpawning = LiveGeofenceTaskSpawner()
    ) {
        self.logger = logger
        self.maxAge = maxAge
        self.requestTimeout = requestTimeout
        self.backgroundTaskRunner = backgroundTaskRunner
        self.dateUtil = dateUtil
        self.waitForTimeout = waitForTimeout
        self.taskSpawner = taskSpawner
        self.desiredAccuracy = desiredAccuracy
        self.diagnosticRecorder = diagnosticRecorder
    }

    deinit {
        timeoutTask?.cancel()
        currentRequestSignal?.complete()
    }

    /// Completes exactly once per call. The `Bool` is whether the coordinates are current: false when
    /// the request failed or timed out and the answer is the stale fallback.
    /// - Parameter admit: called synchronously at the moment this call would issue a new request —
    ///   no current cached answer, and none in flight to join — and never otherwise; false refuses
    ///   it, and the call completes at once with no answer.
    func resolve(
        cached: CLLocation?,
        purpose: GeofenceFixPurpose,
        admit: (() -> Bool)? = nil,
        completion: @escaping (LocationData?, Bool) -> Void
    ) {
        let age = cached.map { self.age(of: $0) }
        if let cached, let age, isCurrent(cached) {
            logger.geofenceMovementFixResolved(ageSeconds: age, requested: false, speed: cached.speed, purpose: purpose)
            // Nothing was asked, so no requested accuracy: that is what tells it from an answer.
            diagnosticRecorder?.record(.fixReceived, returnedAccuracy: cached.horizontalAccuracy, fixAge: age)
            completion(locationData(from: cached), true)
            return
        }
        logger.geofenceMovementFixStale(ageSeconds: age)
        if pendingCompletions.isEmpty, let admit, !admit() {
            completion(nil, false)
            return
        }
        // On a tie the held fallback wins.
        fallbackFix = FixSelection.newest(cached: cached, delivered: fallbackFix)?.fix
        let answered = onCallerWaiting?()
        pendingCompletions.append { location, isFresh in
            answered?()
            completion(location, isFresh)
        }
        guard pendingCompletions.count == 1 else { return }
        // The initiator labels the record; coalesced callers don't log, so one request, one record.
        pendingPurpose = purpose
        requestStartedAt = GeofenceLog.monotonicNow()
        startTimeout()
        holdBackgroundTimeUntilCompletion()
        // Before asking: the answer can arrive synchronously, or after a reset.
        cycleDiagnosticToken = diagnosticRecorder?.token
        diagnosticRecorder?.record(.fixRequested, token: cycleDiagnosticToken, requestedAccuracy: requestedAccuracyLabel)
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
            // A stale echo still answered; a future-dated one is recorded with no age.
            recordAnswerDiagnostic(fix, reason: .staleFix)
            recordDeliveredFix(fix)
            return
        }
        handleResolvedFix(fix)
    }

    func handleResolvedFix(_ fix: CLLocation) {
        recordAnswerDiagnostic(fix, reason: nil)
        recordDeliveredFix(fix)
        guard !pendingCompletions.isEmpty else { return }
        logger.geofenceMovementFixResolved(ageSeconds: age(of: fix), requested: true, speed: fix.speed, purpose: pendingPurpose)
        completeAll(with: locationData(from: fix), isFresh: true)
    }

    func handleRequestFailure() {
        guard !pendingCompletions.isEmpty else { return }
        // The cycle ended unanswered, by error or timeout; a stale fallback is not its answer.
        diagnosticRecorder?.record(
            .fixReceived, token: cycleDiagnosticToken, reason: .noFix, requestedAccuracy: requestedAccuracyLabel
        )
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

    /// An answer Core Location delivered, recorded under the cycle that asked for it.
    private func recordAnswerDiagnostic(_ fix: CLLocation, reason: DwellDiagnosticReason?) {
        guard let diagnosticRecorder, let cycleDiagnosticToken else { return }
        diagnosticRecorder.record(
            .fixReceived, token: cycleDiagnosticToken, reason: reason, requestedAccuracy: requestedAccuracyLabel,
            returnedAccuracy: fix.horizontalAccuracy, fixAge: age(of: fix)
        )
    }

    /// What this resolver asks Core Location for, by name. Read from the stored value, so the
    /// `requestFreshFix` seam still never creates the manager.
    private var requestedAccuracyLabel: String {
        if desiredAccuracy == kCLLocationAccuracyReduced { return "reduced" }
        return Self.accuracyLabels[desiredAccuracy] ?? "custom"
    }

    private static let accuracyLabels: [CLLocationAccuracy: String] = [
        kCLLocationAccuracyBestForNavigation: "best_for_navigation",
        kCLLocationAccuracyBest: "best",
        kCLLocationAccuracyNearestTenMeters: "nearest_ten_meters",
        kCLLocationAccuracyHundredMeters: "hundred_meters",
        kCLLocationAccuracyKilometer: "kilometer",
        kCLLocationAccuracyThreeKilometers: "three_kilometers"
    ]

    private func recordDeliveredFix(_ fix: CLLocation) {
        logger.geofenceFixReceived(fix, source: "movement_resolver", now: dateUtil.now)
        guard !isFuture(fix) else { return }
        if latestFix.map({ fix.timestamp > $0.timestamp }) ?? true {
            deliveredFix = fix
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = taskSpawner.spawn { @MainActor [weak self, requestTimeout, waitForTimeout] in
            await waitForTimeout(requestTimeout)
            guard !Task.isCancelled else { return }
            self?.cancelPendingRequest()
            self?.handleRequestFailure()
        }
    }

    /// A request timed out: Core Location is told to stop it, not just left to answer no one. A
    /// fix it delivers anyway is still recorded.
    private func cancelPendingRequest() {
        guard !pendingCompletions.isEmpty else { return }
        if requestFreshFix != nil {
            cancelFreshFix?()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    /// A region wake's short window may be mostly spent on the request, so hold background time for
    /// the request's life.
    private func holdBackgroundTimeUntilCompletion() {
        let signal = RequestCompletionSignal()
        currentRequestSignal = signal
        let runner = backgroundTaskRunner
        // Holds background time until the request completes; the timeout that completes it is counted.
        // swiftlint:disable:next geofence_untracked_task
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
