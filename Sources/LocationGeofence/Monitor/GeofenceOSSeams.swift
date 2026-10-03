import CioInternalCommon
import CoreLocation
import Foundation

// MARK: - Condition monitoring (CLMonitor)

enum GeofenceConditionState: Sendable, Equatable {
    case satisfied
    case unsatisfied
    case unknown
    /// The OS gave the condition up; it stays listed but is dead until re-added.
    case unmonitored
}

struct GeofenceConditionEvent: Sendable, Equatable {
    let identifier: String
    let state: GeofenceConditionState
    /// OS-dated, not receipt time.
    let date: Date
}

/// Region monitoring as `CLMonitor` provides it.
protocol GeofenceConditionMonitoring: AnyObject, Sendable {
    /// Every condition the OS holds under the SDK's monitor name, including ones it has given up on.
    var identifiers: [String] { get async }
    /// Single-consumer: a second live iteration splits the events rather than duplicating them.
    var events: AsyncThrowingStream<GeofenceConditionEvent, Error> { get async }
    /// `assuming` seeds the OS's belief so a fresh add does not immediately report that state.
    func add(center: LocationData, radius: Double, identifier: String, assuming: GeofenceConditionState) async
    /// A no-op for an identifier the OS is not holding.
    func remove(_ identifier: String) async
}

// MARK: - Authorization and device position (CLLocationManager)

/// The `CLLocationManager` reads the CLMonitor path makes.
protocol GeofenceLocationAuthority: AnyObject {
    /// Never prompts.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Precise rather than approximate location.
    var isFullAccuracy: Bool { get }
    var maximumRegionMonitoringDistance: CLLocationDistance { get }
    var currentLocation: CLLocation? { get }
    /// **Must be invoked on the main actor**: the handler calls `MainActor.assumeIsolated`, which
    /// traps otherwise.
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

@available(iOS 17.0, *)
final class CoreLocationConditionMonitor: GeofenceConditionMonitoring, @unchecked Sendable {
    private let monitor: CLMonitor

    init(monitor: CLMonitor) {
        self.monitor = monitor
    }

    var identifiers: [String] {
        get async { await monitor.identifiers }
    }

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
                            // Don't rely on `onTermination`'s cancel reaching `CLMonitor.Events`:
                            // breaking here guarantees a dead consumer leaves no second live reader.
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
    var isFullAccuracy: Bool { manager.accuracyAuthorization == .fullAccuracy }
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
