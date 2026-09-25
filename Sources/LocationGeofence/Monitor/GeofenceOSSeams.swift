import CioInternalCommon
import CoreLocation
import Foundation

// The OS objects `CLMonitorGeofenceMonitor` talks to, behind protocols it can be handed. Between
// them these cover every OS call the wrapper makes; everything above them is SDK decision.

// MARK: - Condition monitoring (CLMonitor)

/// What a monitored condition is currently known to be. Mirrors `CLMonitor.Event.State`.
enum GeofenceConditionState: Sendable, Equatable {
    case satisfied
    case unsatisfied
    case unknown
    /// The OS gave the condition up; it stays listed but is dead until re-added.
    case unmonitored
}

/// One state report for one condition.
struct GeofenceConditionEvent: Sendable, Equatable {
    let identifier: String
    let state: GeofenceConditionState
    /// When the OS dated the event, not when the SDK received it.
    let date: Date
}

/// Region monitoring as `CLMonitor` provides it.
protocol GeofenceConditionMonitoring: AnyObject, Sendable {
    /// Every condition the OS holds under the SDK's monitor name, including ones it has given up on.
    var identifiers: [String] { get async }
    /// Every state report for every held condition. Single-consumer: a second live iteration
    /// splits the events between the two rather than each seeing all of them.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> { get async }
    /// `assuming` seeds the OS's belief so a fresh add does not immediately report that state.
    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async
    /// Stops monitoring one condition. A no-op for an identifier the OS is not holding.
    func remove(_ identifier: String) async
}

// MARK: - Authorization and device position (CLLocationManager)

/// The `CLLocationManager` reads the CLMonitor path makes.
protocol GeofenceLocationAuthority: AnyObject {
    /// The tier currently granted, read synchronously. Never prompts.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// The OS's cap on a monitored radius; a larger request is clamped to it before registration.
    var maximumRegionMonitoringDistance: CLLocationDistance { get }
    /// The OS's cached position, a pull.
    var currentLocation: CLLocation? { get }
    /// Fired when the granted tier changes.
    ///
    /// **Must be invoked on the main actor.** `CLMonitorGeofenceMonitor` installs a handler that
    /// calls `MainActor.assumeIsolated`, which traps rather than hops if the contract is broken.
    /// The live implementation satisfies it because `CLLocationManagerDelegate` callbacks arrive on
    /// the thread the manager was created on, and the manager is created on the main thread; a
    /// double standing in for it has to honour the same rule.
    var onAuthorizationChange: (() -> Void)? { get set }
    /// Holds a `CLServiceSession` while Always is granted (iOS 18+). Must never prompt.
    func updateServiceSession(isAlwaysAuthorized: Bool)
}

// MARK: - Live implementations

@available(iOS 17.0, *)
extension GeofenceConditionState {
    init(_ state: CLMonitor.Event.State) {
        switch state {
        case .satisfied: self = .satisfied
        case .unsatisfied: self = .unsatisfied
        case .unknown: self = .unknown
        case .unmonitored: self = .unmonitored
        @unknown default: self = .unknown
        }
    }

    /// `CLMonitor.add(assuming:)` accepts only satisfied/unsatisfied; anything else seeds as outside.
    var assumedCLState: CLMonitor.Event.State {
        self == .satisfied ? .satisfied : .unsatisfied
    }
}

/// Adapts `CLMonitor` to `GeofenceConditionMonitoring`. Holds the one monitor: a second with the
/// same name throws "already in use".
@available(iOS 17.0, *)
final class CoreLocationConditionMonitor: GeofenceConditionMonitoring, @unchecked Sendable {
    private let monitor: CLMonitor

    init(monitor: CLMonitor) {
        self.monitor = monitor
    }

    var identifiers: [String] {
        get async { await monitor.identifiers }
    }

    /// Cancelled on termination: two live consumers would split the events between them.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> {
        get async {
            let underlying = await monitor.events
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await event in underlying {
                            let delivered = continuation.yield(
                                GeofenceConditionEvent(
                                    identifier: event.identifier,
                                    state: GeofenceConditionState(event.state),
                                    date: event.date
                                )
                            )
                            // The downstream stream is gone. `onTermination` cancels this task, but
                            // that relies on the cancellation reaching `CLMonitor.Events`, which is
                            // Apple's code; leaving the loop on the yield's own answer does not.
                            // Without it a pump that outlives its consumer is a second live reader
                            // of `monitor.events`, which the class comment says must never happen.
                            if case .terminated = delivered { break }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async {
        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            radius: radius
        )
        await monitor.add(condition, identifier: identifier, assuming: assuming.assumedCLState)
    }

    func remove(_ identifier: String) async {
        await monitor.remove(identifier)
    }
}

/// Adapts `CLLocationManager` to `GeofenceLocationAuthority`, owning the delegate conformance.
@available(iOS 14.0, *)
final class CoreLocationAuthority: NSObject, GeofenceLocationAuthority, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    /// `CLServiceSession`; untyped because a stored property cannot carry availability.
    private var serviceSession: AnyObject?

    var onAuthorizationChange: (() -> Void)?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var maximumRegionMonitoringDistance: CLLocationDistance { manager.maximumRegionMonitoringDistance }
    var currentLocation: CLLocation? { manager.location }

    func updateServiceSession(isAlwaysAuthorized: Bool) {
        guard #available(iOS 18.0, *) else { return }
        if isAlwaysAuthorized {
            guard serviceSession == nil else { return }
            serviceSession = CLServiceSession(authorization: .always)
        } else if let session = serviceSession as? CLServiceSession {
            session.invalidate()
            serviceSession = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?()
    }
}
