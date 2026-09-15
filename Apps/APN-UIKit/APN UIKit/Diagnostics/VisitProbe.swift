import CioInternalCommon
import CoreLocation
import Foundation
import UIKit

/// Measures what `CLVisit` would have given us, without the SDK depending on it.
///
/// The SDK has no wake source while the device is stationary: with the app closed and nothing
/// moving, no movement pass runs, so baseline heal never gets a chance and a dwell crossing is
/// missed outright (measured twice in the field 2026-08-14). `startMonitoringVisits` is the only
/// iOS primitive with dwell semantics that also relaunches a terminated app, so the question for
/// MBL-2433 is whether its wake arrives soon enough to be worth building on.
///
/// This lives in the sample app on purpose. It answers "would CLVisit have woken us in time"
/// without putting an unmeasured OS primitive anywhere near shipped code — the same reasoning the
/// Android session applied to GMS `DWELL`. What it records is the arrival/departure LATENCY, which
/// is the number that decides what dwell support could honestly promise.
@MainActor
final class VisitProbe: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = VisitProbe()

    private static let defaultsKey = "cio_visit_probe"

    /// Lazy so the probe costs nothing when off — not even a manager allocation.
    private lazy var manager = CLLocationManager()
    private var armed = false
    private var sawUnauthorized = false
    private var launchedByLocation = false

    /// Resolves the gate, persisting only an EXPLICIT choice.
    ///
    /// `UserDefaults.bool` already resolves the launch-argument domain over the stored value, but
    /// that domain is volatile: `-cio_visit_probe YES` applies to one process and never reaches
    /// disk. The capture this probe exists for spans an OS relaunch — device still, app killed,
    /// CoreLocation relaunches it to deliver the visit — and the relaunched process gets no
    /// arguments and no environment. Without a write it reads `false`, the probe stays off, and the
    /// visit that woke the app is lost: an outcome indistinguishable from "CLVisit never fired".
    ///
    /// A launch carrying neither only READS. Before the first unlock after a reboot
    /// `UserDefaults.standard` is unreadable under data protection and reports `false` for a key
    /// stored as `true`; writing that reading back would erase the stored `true` and leave the
    /// probe off for every later launch. An overnight stationary capture is exactly when a device
    /// reboots and relaunches into that window, so the read-only path is what keeps a lost window
    /// from becoming a lost capture.
    ///
    /// An explicit value is honoured whatever it says: `CIO_VISIT_PROBE=0`, an empty one, or
    /// `-cio_visit_probe NO` all persist `false` over a stored `true`. That is the intended way
    /// to turn the probe off, and it is a stated choice rather than an unreadable domain.
    ///
    /// Read once at launch, so flipping it takes a relaunch.
    private static func resolveAndPersistGate() -> Bool {
        if let fromEnvironment = ProcessInfo.processInfo.environment["CIO_VISIT_PROBE"] {
            return persistGate(fromEnvironment == "1")
        }
        // The argument domain is read directly rather than through `bool(forKey:)`, which cannot
        // say whether the value it returned came from this launch's arguments or from disk.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let fromArgument = arguments[defaultsKey] {
            let token = String(describing: fromArgument).lowercased()
            return persistGate(["1", "yes", "true"].contains(token))
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    private static func persistGate(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
        return enabled
    }

    func startIfEnabled(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        launchedByLocation = launchOptions?[.location] != nil
        guard Self.resolveAndPersistGate() else { return }
        // Delegate first and unconditionally: visit monitoring needs Always, the SDK asks for it
        // after launch, and without this delegate the grant arrives with nothing listening — the
        // probe would then sit dead for the whole process on any device not already authorized.
        manager.delegate = self
        startIfAuthorized()
    }

    /// Runs from launch and from every authorization change, calling `startMonitoringVisits()`
    /// every time it is authorized rather than once.
    ///
    /// `armed` decides only what gets logged; it deliberately does NOT gate the OS call. After
    /// Always then denied then Always, a one-shot guard would return here and leave monitoring in
    /// whatever state the system left it. Apple documents that region monitoring resumes when the
    /// grant returns but says nothing about visits, and `startMonitoringVisits()` is idempotent,
    /// so re-calling is cheaper than assuming.
    private func startIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        // No `requestAlwaysAuthorization` here: the SDK owns the prompt, and asking twice changes
        // the very authorization state the probe is meant to observe.
        manager.startMonitoringVisits()
        // Setting the delegate always produces one authorization callback, so this runs twice on a
        // normal launch. Only a re-call that FOLLOWS a non-Always status is a real re-arm; logging
        // the other one would put a `rearmed` record in every capture and make the record useless
        // for spotting the downgrade it exists to spot.
        let isRealRearm = armed && sawUnauthorized
        if !armed || isRealRearm {
            DiagnosticLog.shared.note(
                (isRealRearm ? "Visit probe re-armed" : "Visit probe started")
                    + DiagnosticLog.delimiter
                    + "ev=probe.visit.\(isRealRearm ? "rearmed" : "started") io=obs"
                    + " launch=\(launchedByLocation ? "location" : "app_start")",
                level: .info
            )
        }
        armed = true
        sawUnauthorized = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Logged whether or not the probe is waiting, so a capture that produced no visit can be
        // told apart from one where Always was never granted — and so a DOWNGRADE is visible,
        // since the system may have stopped monitoring at that point.
        DiagnosticLog.shared.note(
            "Visit probe saw authorization \(manager.authorizationStatus.rawValue)"
                + DiagnosticLog.delimiter
                + "ev=probe.visit.auth io=obs status=\(manager.authorizationStatus.rawValue)"
                + " armed=\(armed)",
            level: .info
        )
        if manager.authorizationStatus != .authorizedAlways { sawUnauthorized = true }
        startIfAuthorized()
    }

    func locationManager(_: CLLocationManager, didVisit visit: CLVisit) {
        // A visit is reported twice: once when the arrival is recognised, with
        // `departureDate == .distantFuture`, then again when the departure is.
        let departed = visit.departureDate != .distantFuture
        // `arrivalDate` is `.distantPast` when the visit began BEFORE monitoring started — the
        // first visit of every capture, and after every relaunch. Measuring latency against it
        // yields ~2e12 seconds, so the row that matters most would be the one row of garbage.
        let arrivalKnown = visit.arrivalDate != .distantPast
        let reference = departed ? visit.departureDate : visit.arrivalDate
        let latency = (departed || arrivalKnown) ? Date().timeIntervalSince(reference) : nil
        DiagnosticLog.shared.note(
            "CLVisit \(departed ? "departure" : "arrival") reported"
                + DiagnosticLog.delimiter
                + "ev=probe.visit.\(departed ? "departed" : "arrived") io=in"
                + " lat=\(fmt(visit.coordinate.latitude, 6)) lon=\(fmt(visit.coordinate.longitude, 6))"
                + " acc=\(fmt(visit.horizontalAccuracy, 1))"
                + " arrival=\(arrivalKnown ? iso(visit.arrivalDate) : "before_monitoring")"
                + " departure=\(departed ? iso(visit.departureDate) : "pending")"
                + " lat_dp=\(latency.map { fmt($0, 1) } ?? "nan")"
                // Live delivery or an OS relaunch — the relaunch is the case the ticket is about,
                // and the two are otherwise indistinguishable in the log.
                + " state=\(stateToken())"
                // A CoreLocation wake, NOT proof that CLVisit caused it: `.location` is set for any
                // of them, the SDK's own geofence wake included. Read it as "the OS relaunched us
                // for location" and take the latency, not the cause, from the visit dates.
                + " launch=\(launchedByLocation ? "location" : "app_start")",
            level: .info
        )
    }

    private func stateToken() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private func fmt(_ value: Double, _ places: Int) -> String {
        value.isFinite ? String(format: "%.\(places)f", value) : "nan"
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
