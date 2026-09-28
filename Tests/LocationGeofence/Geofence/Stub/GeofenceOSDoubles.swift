@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

// Doubles for `CLMonitor` and `CLLocationManager`, on the seams `GeofenceOSSeams.swift` draws.
// Only the OS is substituted, so `CLMonitorGeofenceMonitor`'s own decisions (FIFO pipeline, adopt
// and re-arm, contradiction gate, baseline heal) run for real.

/// What the SDK handed to the host, recorded from any thread.
///
/// `GeofenceTransitionHandler` is `@Sendable` and is not called on the main actor, so a plain
/// captured array appended there and read from a test body is a data race.
final class DeliveredTransitions: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(identifier: String, transition: GeofenceTransition)] = []

    var all: [(identifier: String, transition: GeofenceTransition)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var isEmpty: Bool { all.isEmpty }

    var description: String {
        all.map { "\($0.identifier):\($0.transition.rawValue)" }.joined(separator: ", ")
    }

    func record(_ identifier: String, _ transition: GeofenceTransition) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append((identifier, transition))
    }
}

/// The OS's region monitor: holds conditions, and reports state for them when a test says it did.
///
/// Deliberately dumb: every decision about what an event means belongs to the wrapper.
@MainActor
final class FakeConditionMonitor: GeofenceConditionMonitoring {
    /// A condition as the OS holds it, post-clamp.
    struct HeldCondition: Equatable {
        let center: LocationData
        let radius: Double
        let assumed: GeofenceConditionState
    }

    private(set) var held: [String: HeldCondition] = [:]
    /// Every add/remove in arrival order, so a test can assert the OS was driven in the right order.
    private(set) var operations: [String] = []

    private var continuation: AsyncThrowingStream<GeofenceConditionEvent, Error>.Continuation?

    /// Callers parked inside `add`/`remove` while the OS is held.
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var isHeld = false

    var identifiers: [String] {
        get async { held.keys.sorted() }
    }

    /// A fresh stream per subscriber, and only the newest one is fed. A replayed `process.start`
    /// builds a second wrapper while the dead process's consumer is still parked on the old
    /// stream; leaving that one quiet is what a dead process looks like from the OS side.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> {
        get async {
            AsyncThrowingStream { self.continuation = $0 }
        }
    }

    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async {
        await parkWhileHeld()
        // Mirrors CLMonitor: an add over a live identifier is silently ignored and the original
        // circle survives, which is why the wrapper removes first.
        guard held[identifier] == nil else { return }
        held[identifier] = HeldCondition(center: center, radius: radius, assumed: assuming)
        operations.append("add(\(identifier))")
    }

    func remove(_ identifier: String) async {
        await parkWhileHeld()
        guard held.removeValue(forKey: identifier) != nil else { return }
        operations.append("remove(\(identifier))")
    }

    /// Seeds a condition a previous process left behind, without recording an operation.
    func preload(identifier: String, center: LocationData, radius: Double, assuming: GeofenceConditionState) {
        held[identifier] = HeldCondition(center: center, radius: radius, assumed: assuming)
    }

    /// Delivers one OS event through the `events` stream, so it passes the wrapper's pending-event
    /// queue, ownership filter and `.unmonitored` handling like a real one.
    func deliver(identifier: String, state: GeofenceConditionState, at date: Date) {
        guard let continuation else {
            deliveredWithNoSubscriber += 1
            return
        }
        continuation.yield(GeofenceConditionEvent(identifier: identifier, state: state, date: date))
    }

    /// Events pushed in with nobody listening. The wrapper subscribes asynchronously at init, so an
    /// early crossing is lost; counted so it doesn't read as the SDK ignoring a callback.
    private(set) var deliveredWithNoSubscriber = 0

    var hasSubscriber: Bool { continuation != nil }

    /// Parks `add`/`remove` until `releaseOperations()`, opening the window where an event arrives
    /// while a mutation is still in flight. A fake that answers instantly never opens it.
    func holdOperations() {
        isHeld = true
    }

    func releaseOperations() {
        isHeld = false
        let waiting = parked
        parked.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Whether anything is currently parked.
    var hasParkedOperation: Bool { !parked.isEmpty }

    private func parkWhileHeld() async {
        guard isHeld else { return }
        await withCheckedContinuation { continuation in
            parked.append(continuation)
        }
    }

    func resetOperations() {
        operations.removeAll()
    }

    /// Between runs. Parked callers are resumed, not dropped: a run that failed while held would
    /// otherwise wedge the next run's first `add`. The stream is finished so `hasSubscriber` does
    /// not report the previous run's subscriber.
    func reset() {
        held.removeAll()
        operations.removeAll()
        deliveredWithNoSubscriber = 0
        isHeld = false
        let waiting = parked
        parked.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
        continuation?.finish()
        continuation = nil
    }
}

/// Authorization, the OS radius cap, and the cached position.
///
/// `currentLocation` is the `manager_cache` pull; answering it here lets the real fix-selection code
/// decide what to do with the answer.
@MainActor
final class FakeLocationAuthority: GeofenceLocationAuthority {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    /// Large enough that clamping never fires unless a test sets it.
    var maximumRegionMonitoringDistance: CLLocationDistance = 100000

    var onAuthorizationChange: (() -> Void)?

    /// What the OS cache answers. A closure so a test can move the device between reads.
    var answerCachedLocation: (() -> CLLocation?)?

    /// Recorded, not acted on: there is no OS to hold a session with.
    private(set) var isHoldingServiceSession = false

    /// Counted, never asserted: how often a position is read is implementation, not behaviour.
    private(set) var cacheReadCount = 0

    var currentLocation: CLLocation? {
        cacheReadCount += 1
        return answerCachedLocation?()
    }

    func updateServiceSession(isAlwaysAuthorized: Bool) {
        isHoldingServiceSession = isAlwaysAuthorized
    }

    /// Changes the tier, then notifies, as the OS does.
    func setAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        onAuthorizationChange?()
    }

    func reset() {
        authorizationStatus = .authorizedAlways
        cacheReadCount = 0
        isHoldingServiceSession = false
    }
}
