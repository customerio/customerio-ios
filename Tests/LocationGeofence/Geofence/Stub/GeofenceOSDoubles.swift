@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

// Only the OS is substituted, so `CLMonitorGeofenceMonitor`'s own logic runs for real.

/// `@unchecked Sendable`: state is behind `lock`; the transition handler runs off the main actor.
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

/// Deliberately dumb: every decision about what an event means belongs to the wrapper.
@MainActor
final class FakeConditionMonitor: GeofenceConditionMonitoring {
    /// Post-clamp.
    struct HeldCondition: Equatable {
        let center: LocationData
        let radius: Double
        let assumed: GeofenceConditionState
    }

    private(set) var held: [String: HeldCondition] = [:]
    private(set) var operations: [String] = []

    private var continuation: AsyncThrowingStream<GeofenceConditionEvent, Error>.Continuation?

    private var parked: [CheckedContinuation<Void, Never>] = []
    private var isHeld = false

    var identifiers: [String] {
        get async { held.keys.sorted() }
    }

    /// Only the newest subscriber is fed, so a replaced wrapper's consumer stays quiet like a dead
    /// process.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> {
        get async {
            AsyncThrowingStream { self.continuation = $0 }
        }
    }

    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async {
        await parkWhileHeld()
        // Mirrors CLMonitor: an add over a live identifier is ignored; the original circle survives.
        guard held[identifier] == nil else { return }
        held[identifier] = HeldCondition(center: center, radius: radius, assumed: assuming)
        operations.append("add(\(identifier))")
    }

    func remove(_ identifier: String) async {
        await parkWhileHeld()
        guard held.removeValue(forKey: identifier) != nil else { return }
        operations.append("remove(\(identifier))")
    }

    /// Not recorded in `operations`.
    func preload(identifier: String, center: LocationData, radius: Double, assuming: GeofenceConditionState) {
        held[identifier] = HeldCondition(center: center, radius: radius, assumed: assuming)
    }

    func deliver(identifier: String, state: GeofenceConditionState, at date: Date) {
        guard let continuation else {
            deliveredWithNoSubscriber += 1
            return
        }
        continuation.yield(GeofenceConditionEvent(identifier: identifier, state: state, date: date))
    }

    /// The wrapper subscribes asynchronously, so an early event is dropped; counted to make that
    /// visible.
    private(set) var deliveredWithNoSubscriber = 0

    var hasSubscriber: Bool { continuation != nil }

    /// Parks `add`/`remove` until `releaseOperations()`, so an event can land mid-mutation.
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

    /// Resumes parked callers rather than dropping them, or the next run's first `add` wedges.
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

@MainActor
final class FakeLocationAuthority: GeofenceLocationAuthority {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    /// Large enough that clamping never fires.
    var maximumRegionMonitoringDistance: CLLocationDistance = 100000

    var onAuthorizationChange: (() -> Void)?

    var answerCachedLocation: (() -> CLLocation?)?

    private(set) var isHoldingServiceSession = false

    /// Don't assert on it: read count is implementation, not behaviour.
    private(set) var cacheReadCount = 0

    var currentLocation: CLLocation? {
        cacheReadCount += 1
        return answerCachedLocation?()
    }

    func updateServiceSession(isAlwaysAuthorized: Bool) {
        isHoldingServiceSession = isAlwaysAuthorized
    }

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
