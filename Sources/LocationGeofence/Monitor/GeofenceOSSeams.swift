import CioInternalCommon
import CoreLocation
import Foundation

// The OS objects `CLMonitorGeofenceMonitor` talks to, behind protocols it can be handed.
//
// **Why these exist.** The wrapper is not a humble object: alongside its CoreLocation calls it owns
// real policy — the FIFO mutation pipeline, the foreground re-arm interval, the contradiction gate,
// which regions are baseline-heal candidates. A test that substitutes the *whole wrapper* therefore
// has to re-create that policy, and a re-created rule is one that stops matching the SDK the moment
// the SDK changes, silently. The replay harness had already grown three such copies.
//
// The line these protocols draw is the line where CoreLocation actually starts, which is the only
// line worth substituting along. Everything above it — every decision — then runs for real.
//
// Deliberately narrow: between them these cover every OS call the wrapper makes. Adding to them
// should feel like a decision, because each addition is another thing a replay has to answer for.

// MARK: - Condition monitoring (CLMonitor)

/// What a monitored condition is currently known to be.
///
/// Mirrors `CLMonitor.Event.State` rather than reusing it, so the wrapper's own logic — and the
/// tests that drive it — need no iOS 17 availability dance and no CoreLocation instance.
enum GeofenceConditionState: Sendable, Equatable {
    case satisfied
    case unsatisfied
    /// The OS holds the condition but cannot currently place the device.
    case unknown
    /// The OS gave the condition up (condition budget, typically). It stays listed but is dead
    /// until re-added — see the `.unmonitored` handling in `CLMonitorGeofenceMonitor.process`.
    case unmonitored
}

/// One state report for one condition. The three fields are everything the wrapper reads.
struct GeofenceConditionEvent: Sendable, Equatable {
    let identifier: String
    let state: GeofenceConditionState
    /// When the OS dated the event, which is not when the SDK processed it — the gap is `evage`.
    let date: Date
}

/// Region monitoring as `CLMonitor` provides it.
///
/// `events` is a stream rather than a callback because that is CoreLocation's own shape, and the
/// wrapper's re-subscribe-with-backoff loop depends on it ending or throwing.
protocol GeofenceConditionMonitoring: AnyObject, Sendable {
    /// Every condition the OS holds under the SDK's monitor name, including ones it has given up on.
    var identifiers: [String] { get async }
    /// The event stream. Ending or throwing is a real condition the wrapper recovers from.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> { get async }
    /// Adds a circular condition, seeding the OS's belief about the device's current position.
    ///
    /// `assuming` is what stops a fresh add from immediately reporting the state it was added in.
    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async
    func remove(_ identifier: String) async
}

// MARK: - Authorization and device position (CLLocationManager)

/// The `CLLocationManager` reads the CLMonitor path makes.
///
/// Not "a location manager": only the four things this wrapper actually asks one for. `location` is
/// here because it is the OS *cache* read — the `manager_cache` fix the SDK decides from — and a
/// replay that cannot answer it cannot exercise any decision that reads a position.
protocol GeofenceLocationAuthority: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var maximumRegionMonitoringDistance: CLLocationDistance { get }
    /// The OS's cached position. A *pull*: reading it leaves no trace unless the SDK logs one.
    var currentLocation: CLLocation? { get }
    /// Called whenever the granted tier changes.
    var onAuthorizationChange: (() -> Void)? { get set }
    /// Asserts continued background interest while Always is granted (iOS 18+ `CLServiceSession`).
    ///
    /// Behind the seam because the session is an OS resource: a test that reported Always would
    /// otherwise open a real one. Implementations must never prompt — a session above the granted
    /// tier can, and prompting is the host app's decision.
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

    /// The subset `CLMonitor.add(_:identifier:assuming:)` accepts. Anything else is not a belief the
    /// OS can be seeded with, so it is treated as "outside" — the same default a missing record gets.
    @available(iOS 17.0, *)
    var assumedCLState: CLMonitor.Event.State {
        self == .satisfied ? .satisfied : .unsatisfied
    }
}

/// Adapts Apple's `CLMonitor` actor to `GeofenceConditionMonitoring`.
///
/// Holds the monitor rather than creating one per call: a second `CLMonitor` with the same name
/// throws "Monitor named ... is already in use".
@available(iOS 17.0, *)
final class CoreLocationConditionMonitor: GeofenceConditionMonitoring, @unchecked Sendable {
    private let monitor: CLMonitor

    init(monitor: CLMonitor) {
        self.monitor = monitor
    }

    var identifiers: [String] {
        get async { await monitor.identifiers }
    }

    /// Bridges `CLMonitor.Events` into a stream of the wrapper's own event type.
    ///
    /// The bridging task is cancelled when the consumer stops, so a re-subscribe does not leave the
    /// previous one attached — two live consumers would split the events between them rather than
    /// each seeing all of them.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> {
        get async {
            let underlying = await monitor.events
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await event in underlying {
                            continuation.yield(
                                GeofenceConditionEvent(
                                    identifier: event.identifier,
                                    state: GeofenceConditionState(event.state),
                                    date: event.date
                                )
                            )
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

/// Adapts `CLLocationManager` to `GeofenceLocationAuthority`, owning the delegate conformance so
/// the wrapper above it does not have to be an `NSObject`.
///
/// iOS 14 for the instance `authorizationStatus`; its only caller is the iOS 17+ CLMonitor path, so
/// the floor costs nothing. The classic monitor keeps reading `CLLocationManager` directly.
@available(iOS 14.0, *)
final class CoreLocationAuthority: NSObject, GeofenceLocationAuthority, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    /// Held for the monitor's lifetime while Always is granted. Untyped because a stored property
    /// cannot carry availability.
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
