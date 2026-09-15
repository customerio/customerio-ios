import CioInternalCommon
import CoreLocation
import Foundation

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
final class VisitProbe: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    // Touched only on the main queue: started from `didFinishLaunching` and the delegate callback
    // arrives on the queue the manager was created on, which is that same one.
    static let shared = VisitProbe()

    private let manager = CLLocationManager()
    private var started = false

    /// Opt-in, and deliberately NOT an environment variable alone.
    ///
    /// The capture this probe exists for spans an OS relaunch: the device sits still, the app is
    /// killed, and CoreLocation relaunches it to deliver the visit. Nothing launched that way
    /// carries an environment, so an env-only gate would be off for exactly the event being
    /// measured. `UserDefaults` survives it. Set it once with the launch argument
    /// `-cio_visit_probe YES` (UserDefaults reads launch arguments directly) and it stays on.
    /// The env var is kept only because `simctl` can set it and a simulator has no Xcode launch.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "cio_visit_probe")
            || ProcessInfo.processInfo.environment["CIO_VISIT_PROBE"] == "1"
    }

    func startIfEnabled() {
        guard Self.isEnabled else { return }
        // Delegate first and unconditionally: visit monitoring needs Always, the SDK asks for it
        // after launch, and without this delegate the grant arrives with nothing listening — the
        // probe would then sit dead for the whole process on any device not already authorized.
        manager.delegate = self
        startIfAuthorized()
    }

    /// Idempotent, because it runs from launch AND from every authorization change.
    private func startIfAuthorized() {
        guard !started, manager.authorizationStatus == .authorizedAlways else { return }
        started = true
        // No `requestAlwaysAuthorization` here: the SDK owns the prompt, and asking twice changes
        // the very authorization state the probe is meant to observe.
        manager.startMonitoringVisits()
        DiagnosticLog.shared.note(
            "Visit probe started\(DiagnosticLog.delimiter)ev=probe.visit.started io=obs",
            level: .info
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Reported whether or not the probe is waiting, so a capture that produced no visit can be
        // told apart from one where Always was never granted.
        DiagnosticLog.shared.note(
            "Visit probe saw authorization \(manager.authorizationStatus.rawValue)"
                + DiagnosticLog.delimiter
                + "ev=probe.visit.auth io=obs status=\(manager.authorizationStatus.rawValue)"
                + " armed=\(started)",
            level: .info
        )
        startIfAuthorized()
    }

    func locationManager(_: CLLocationManager, didVisit visit: CLVisit) {
        // A visit is reported twice: once with `departureDate == .distantFuture` when the arrival
        // is recognised, then again when the departure is. `lat`/`lon` follow the SDK's key names
        // so one parser reads both. `lat_dp` is the reporting latency in seconds — the whole point
        // of the probe, and the number the Android session asked for.
        let departed = visit.departureDate != .distantFuture
        let reference = departed ? visit.departureDate : visit.arrivalDate
        let latency = Date().timeIntervalSince(reference)
        let event = departed ? "probe.visit.departed" : "probe.visit.arrived"
        DiagnosticLog.shared.note(
            "CLVisit \(departed ? "departure" : "arrival") reported"
                + DiagnosticLog.delimiter
                + "ev=\(event) io=in"
                + " lat=\(fmt(visit.coordinate.latitude, 6)) lon=\(fmt(visit.coordinate.longitude, 6))"
                + " acc=\(fmt(visit.horizontalAccuracy, 1))"
                + " arrival=\(iso(visit.arrivalDate))"
                + " departure=\(departed ? iso(visit.departureDate) : "pending")"
                + " lat_dp=\(fmt(latency, 1))",
            level: .info
        )
    }

    private func fmt(_ value: Double, _ places: Int) -> String {
        value.isFinite ? String(format: "%.\(places)f", value) : "nan"
    }

    private func iso(_ date: Date) -> String {
        date == .distantFuture ? "pending" : ISO8601DateFormatter().string(from: date)
    }
}
