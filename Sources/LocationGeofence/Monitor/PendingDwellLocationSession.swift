import CoreLocation
import Foundation

/// Which Core Location delegate callback reached the session's manager, without its payload. A callback
/// shows only that Core Location called the manager: it can arrive in the foreground, and the
/// authorization one arrives just after the manager is created, so none shows that iOS woke the process.
enum PendingDwellSessionCallback: Equatable, Sendable {
    case locationUpdate, locationError, authorizationChange

    /// The journal event that records this callback.
    var diagnosticEvent: DwellDiagnosticEvent {
        switch self {
        case .locationUpdate: return .sessionLocationCallback
        case .locationError: return .sessionErrorCallback
        case .authorizationChange: return .sessionAuthorizationCallback
        }
    }
}

/// The manager behind `PendingDwellLocationSession`, a protocol so tests need no Core Location. It
/// exposes no authorization request: the session never prompts.
protocol PendingDwellLocationManaging: AnyObject {
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    /// Told which callback Core Location made, never what it carried: the manager discards each
    /// location and error unread. Core Location's own cached location is outside the manager's control.
    var onActivity: (@MainActor (PendingDwellSessionCallback) -> Void)? { get set }
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

/// The host's explicit, experimental opt-in, read from Info.plist so a background launch that never
/// initializes the SDK still sees it. Off unless the key is a Bool `true`.
struct PendingDwellCollectionOptIn: Equatable {
    static let key = "CIOGeofenceExperimentalPendingDwellBackgroundCollection"
    let enabled: Bool
    /// `UIBackgroundModes` includes `location`; enabling background updates without it throws.
    let declaresBackgroundLocation: Bool

    init(infoValue: (String) -> Any?) {
        self.enabled = infoValue(Self.key) as? Bool ?? false
        self.declaresBackgroundLocation = (infoValue("UIBackgroundModes") as? [String])?.contains("location") ?? false
    }

    init(bundle: Bundle) {
        self.init(infoValue: bundle.object(forInfoDictionaryKey:))
    }
}

/// Asks Core Location to keep the process running while polygon dwells are pending, so their
/// in-process deadlines can fire and request the usual fresh, strict proof. Only an opportunity: the
/// session discards its own fixes and passes none to the resolver.
/// Experimental: whether iOS keeps a 3 km session alive in the background is unqualified on devices.
/// The owner decides when it runs; start and stop are idempotent.
@MainActor
final class PendingDwellLocationSession {
    private let optIn: PendingDwellCollectionOptIn
    private let access: @MainActor () -> GeofenceLocationAccess?
    private let makeManager: @MainActor () -> PendingDwellLocationManaging
    private let notifyOwner: @MainActor () -> Void
    private let diagnosticRecorder: DwellDiagnosticRecorder?
    private var manager: PendingDwellLocationManaging?
    /// The recorder's token when this run started, nil while stopped. Each record of a run carries it,
    /// so the recorder drops what a run started before an identity clear reports after it.
    private var diagnosticToken: UInt64?

    /// - Parameters:
    ///   - access: what the app can use now, Background App Refresh included. Unknown is ineligible.
    ///   - diagnosticRecorder: traces actual starts, stops and callbacks; nil records nothing.
    ///   - onActivity: told that Core Location called back, for every kind, authorization included, to
    ///     reconcile the owner's leases. It must not hold the owner strongly.
    init(
        optIn: PendingDwellCollectionOptIn,
        access: @escaping @MainActor () -> GeofenceLocationAccess?,
        makeManager: @escaping @MainActor () -> PendingDwellLocationManaging = { CoreLocationPendingDwellManager() },
        diagnosticRecorder: DwellDiagnosticRecorder? = nil,
        onActivity: @escaping @MainActor () -> Void
    ) {
        self.optIn = optIn
        self.access = access
        self.makeManager = makeManager
        self.diagnosticRecorder = diagnosticRecorder
        self.notifyOwner = onActivity
    }

    deinit {
        // The owner stops a session it no longer needs; this covers one released while running.
        manager?.stopUpdatingLocation()
    }

    var isOptedIn: Bool { optIn.enabled }
    var isRunning: Bool { manager != nil }

    /// Opted in, the background mode declared, and Always with precise location.
    var isEligible: Bool {
        guard optIn.enabled, optIn.declaresBackgroundLocation, let access = access() else { return false }
        return access.observesBackground && access.fullAccuracy
    }

    /// Starts unless ineligible, which also stops a running session. Returns whether it runs.
    @discardableResult
    func start() -> Bool {
        guard isEligible else {
            stop()
            return false
        }
        guard manager == nil else { return true }
        let manager = makeManager()
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = Self.distanceFilterMeters
        // Paused updates let a parked device suspend, which is the stay this session exists for.
        manager.pausesLocationUpdatesAutomatically = false
        // Only after the eligibility check: without the background mode this throws.
        manager.allowsBackgroundLocationUpdates = true
        manager.onActivity = { [weak self] callback in self?.callbackReported(callback) }
        // Recorded before starting, so an owner the start re-enters sees it running.
        self.manager = manager
        // Before starting too, so a callback the start provokes is traced under this run's token.
        diagnosticToken = diagnosticRecorder?.token
        record(.sessionStarted)
        manager.startUpdatingLocation()
        return true
    }

    func stop() {
        guard let manager else { return }
        // Cleared first, so a callback the stop provokes neither reaches the owner nor sees it running.
        self.manager = nil
        manager.onActivity = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        record(.sessionStopped)
        diagnosticToken = nil
    }

    /// Records which callback came, then runs the owner's reconcile for every kind, so a permission
    /// change, the one delivered at creation included, is still caught. Nothing here feeds a fix,
    /// requests evidence or touches a retry budget.
    private func callbackReported(_ callback: PendingDwellSessionCallback) {
        record(callback.diagnosticEvent)
        notifyOwner()
    }

    /// Only under this run's token. Without one nothing is recorded: the current token would
    /// attribute a callback from an earlier identity's run to the identity now in force.
    private func record(_ event: DwellDiagnosticEvent) {
        guard let diagnosticRecorder, let diagnosticToken else { return }
        diagnosticRecorder.record(event, token: diagnosticToken)
    }

    private static let distanceFilterMeters: CLLocationDistance = 3000
}

/// The Core Location side of the session. Built on the main actor, so Core Location calls back on
/// the main thread. Each callback reports only its kind; its locations and errors are discarded here,
/// unread.
final class CoreLocationPendingDwellManager: NSObject, PendingDwellLocationManaging, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    var onActivity: (@MainActor (PendingDwellSessionCallback) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    deinit { locationManager.stopUpdatingLocation() }

    var desiredAccuracy: CLLocationAccuracy {
        get { locationManager.desiredAccuracy }
        set { locationManager.desiredAccuracy = newValue }
    }

    var distanceFilter: CLLocationDistance {
        get { locationManager.distanceFilter }
        set { locationManager.distanceFilter = newValue }
    }

    var pausesLocationUpdatesAutomatically: Bool {
        get { locationManager.pausesLocationUpdatesAutomatically }
        set { locationManager.pausesLocationUpdatesAutomatically = newValue }
    }

    var allowsBackgroundLocationUpdates: Bool {
        get { locationManager.allowsBackgroundLocationUpdates }
        set { locationManager.allowsBackgroundLocationUpdates = newValue }
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        report(.locationUpdate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        report(.locationError)
    }

    /// Also delivered once just after this manager is created, whatever the app's state.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        report(.authorizationChange)
    }

    private func report(_ callback: PendingDwellSessionCallback) {
        MainActor.assumeIsolated { onActivity?(callback) }
    }
}
