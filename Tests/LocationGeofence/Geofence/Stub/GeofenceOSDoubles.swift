@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

// CoreLocation, as a test can drive it.
//
// These two stand exactly where `CLMonitor` and `CLLocationManager` stand, on the seams
// `GeofenceOSSeams.swift` draws. Nothing else about `CLMonitorGeofenceMonitor` is substituted, so
// its FIFO mutation pipeline, its adopt and re-arm rules, the contradiction gate and the
// baseline-heal enqueue all run for real. That matters: the wrapper is not a humble object, and a
// double that replaced the whole class would replace those decisions too.

/// What the SDK handed to the host, recorded from any thread.
///
/// `GeofenceTransitionHandler` is `@Sendable`: the wrapper calls it from whatever context the event
/// arrived on, which is not the main actor. A plain captured array appended there and read from a
/// test body is a data race — the kind that corrupts a neighbouring read rather than failing here.
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
/// Deliberately dumb. It records what it was told to hold and yields the events pushed into it;
/// every decision about whether an event means anything belongs to the wrapper above.
@MainActor
final class FakeConditionMonitor: GeofenceConditionMonitoring {
    /// A condition as the OS holds it, post-clamp — the OS's own view, not the caller's request.
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

    /// A fresh stream per subscriber, and only the newest one is fed. `AsyncThrowingStream` is
    /// single-consumer: two live iterations split the events rather than each seeing all of them.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> {
        get async {
            AsyncThrowingStream { self.continuation = $0 }
        }
    }

    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async {
        await parkWhileHeld()
        // Mirrors CLMonitor: an add over a live identifier is silently ignored and the original
        // circle survives. The wrapper removes first for exactly this reason, so honouring it here
        // is what keeps that remove-then-add pair honest.
        guard held[identifier] == nil else { return }
        held[identifier] = HeldCondition(center: center, radius: radius, assumed: assuming)
        operations.append("add(\(identifier))")
    }

    func remove(_ identifier: String) async {
        await parkWhileHeld()
        guard held.removeValue(forKey: identifier) != nil else { return }
        operations.append("remove(\(identifier))")
    }

    /// Seeds a condition the way a previous process would have left it, without recording an
    /// operation — these are conditions the OS already held when this process started.
    func preload(identifier: String, center: LocationData, radius: Double, assuming: GeofenceConditionState) {
        held[identifier] = HeldCondition(center: center, radius: radius, assumed: assuming)
    }

    /// Delivers one OS event through the same stream `CLMonitor.events` feeds, so it enters the SDK
    /// by the one door the OS uses — including the wrapper's pending-event queue, its ownership
    /// filter and its `.unmonitored` handling.
    func deliver(identifier: String, state: GeofenceConditionState, at date: Date) {
        continuation?.yield(GeofenceConditionEvent(identifier: identifier, state: state, date: date))
    }

    var hasSubscriber: Bool { continuation != nil }

    /// Makes the OS slow to answer, so a test can put work behind an operation that has not
    /// returned yet.
    ///
    /// The wrapper runs every OS mutation on one serial pipeline, and several of its rules are
    /// about what happens to an event that arrives while an operation is still in flight — the
    /// window a fake that answers instantly can never open. On the 2026-09-12 drive that window
    /// was where the spurious events were delivered.
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

    /// Whether anything is currently parked — a test waits on this rather than guessing.
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
}

/// Authorization, the OS radius cap, and the cached position.
///
/// `currentLocation` is the interesting one: it is the `manager_cache` *pull*, the read the SDK
/// makes whenever it needs a position. Answering it here means the real fix-selection code decides
/// what to do with the answer, rather than a stand-in deciding for it.
@MainActor
final class FakeLocationAuthority: GeofenceLocationAuthority {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    /// Large enough that clamping never fires unless a test sets it deliberately. The real value is
    /// around 100 km on device.
    var maximumRegionMonitoringDistance: CLLocationDistance = 100000

    var onAuthorizationChange: (() -> Void)?

    /// What the OS cache answers. A closure so a test can move the device between reads.
    var answerCachedLocation: (() -> CLLocation?)?

    /// Whether a background session is being held. Recorded rather than acted on: there is no OS to
    /// assert interest to, and the SDK's only requirement is that it asks at the right times.
    private(set) var isHoldingServiceSession = false

    var currentLocation: CLLocation? { answerCachedLocation?() }

    func updateServiceSession(isAlwaysAuthorized: Bool) {
        isHoldingServiceSession = isAlwaysAuthorized
    }

    /// Changes the granted tier the way the OS would, telling the SDK afterwards.
    func setAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        onAuthorizationChange?()
    }
}
