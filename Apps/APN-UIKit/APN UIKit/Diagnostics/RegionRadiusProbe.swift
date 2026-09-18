import CioInternalCommon
import CoreLocation
import Foundation
import UIKit

/// Measures the smallest region radius iOS actually promotes, because the SDK's 100 m wake floor
/// has never been checked.
///
/// `GeofenceConstants.polygonWakeMinRadius = 100` is the reason the in-circle dead zone has no
/// cheap fix. A device that crosses a covering circle while still outside the ring gets no further
/// wake: the covering-circle ENTER does not re-arm the movement trigger, and even if it did, a
/// boundary nearer than 100 m cannot be armed against. Measured on 09-17 at Bundu Khan — circle
/// enter 45 m outside the ring, then 11 min 33 s of nothing, and the arrival landed only when the
/// user walked back to the car and the movement trigger fired.
///
/// Nothing in the SDK imposes a lower bound elsewhere: `resolvedPolygon` registers
/// `enclosingCircle.baseRadiusM` verbatim and `startMonitoring` clamps only the upper end against
/// `maximumRegionMonitoringDistance`. So this measures an unmeasured part of what we already do,
/// not a new capability — and the smallest circle the field has ever exercised is ~100 m
/// (Le Mandarin 100, Rainbow 101, Tim Hortons 109), all of which promote. Below 100 m is
/// unmeasured, not known-bad, and the accuracy that would have to support it is comfortable:
/// 1640 polygon verdicts at median 5.5 m, p90 9.5 m, max 15.5 m.
///
/// **The 100 m ring is the control.** It is known to work, so a capture where it stayed silent
/// says the user never moved far enough and the smaller radii prove nothing. Reading a null from
/// the small rings without checking the control is how this measurement produces a confident wrong
/// answer.
///
/// Armed at the device's own position, so the first crossings are EXITs, not ENTERs — the rings
/// are left behind on the way out and re-entered on the way back. Both are registered and both
/// count as promotion evidence.
///
/// Sample-app only, deliberately. It answers "what floor could the SDK honestly use" without
/// putting an unmeasured radius anywhere near shipped code, the same reasoning as ``VisitProbe``.
@MainActor
final class RegionRadiusProbe: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = RegionRadiusProbe()

    private static let defaultsKey = "cio_region_radius_probe"
    private static let identifierPrefix = "cio_probe_r"

    /// Four rings, concentric on wherever the probe is armed. 100 is the control; the rest are the
    /// question. Kept to four because the OS budget is 20 per app and the SDK registers 13, so
    /// three slots stay free for its own growth during a capture.
    private static let radii: [Double] = [25, 50, 75, 100]

    /// A coarse anchor puts every ring in the wrong place, so the fix is retried rather than
    /// accepted. Bounded because `requestLocation` costs a GPS session each time and a device
    /// indoors will never produce a good one.
    private static let maxAnchorAttempts = 4

    /// Lazy so a launch that says nothing about the probe costs nothing — not even a manager
    /// allocation. An explicit disable does allocate, because stopping needs a manager.
    private lazy var manager = CLLocationManager()
    private var armed = false
    private var anchor: CLLocationCoordinate2D?
    private var armedAt: Date?
    private var anchorAttempts = 0
    private var launchedByLocation = false

    /// Three outcomes, not two: `off` and `disabled` both mean "do not record", but only the
    /// second is a launch SAYING so, and only the second may tear down the OS registration.
    ///
    /// The persistence rule is ``VisitProbe``'s and is load-bearing for the same reason: region
    /// monitoring survives process death, the capture spans an OS relaunch, and the relaunched
    /// process gets no arguments and no environment. A launch carrying neither only READS, because
    /// before the first unlock after a reboot `UserDefaults` reports `false` for a key stored as
    /// `true`, and writing that reading back would turn a lost window into a lost capture.
    private enum Gate {
        case enabled
        case disabled
        case off
    }

    private static func resolveGate() -> Gate {
        if let fromEnvironment = ProcessInfo.processInfo.environment["CIO_REGION_RADIUS_PROBE"] {
            return persistGate(fromEnvironment == "1")
        }
        // The argument domain is read directly rather than through `bool(forKey:)`, which cannot
        // say whether the value it returned came from this launch's arguments or from disk.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let fromArgument = arguments[defaultsKey] {
            let token = String(describing: fromArgument).lowercased()
            return persistGate(["1", "yes", "true"].contains(token))
        }
        return UserDefaults.standard.bool(forKey: defaultsKey) ? .enabled : .off
    }

    private static func persistGate(_ enabled: Bool) -> Gate {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
        return enabled ? .enabled : .disabled
    }

    func startIfEnabled(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        launchedByLocation = launchOptions?[.location] != nil
        switch Self.resolveGate() {
        case .enabled:
            break
        case .disabled:
            stop()
            return
        case .off:
            return
        }
        // Delegate first and unconditionally: region monitoring needs Always, the SDK asks for it
        // after launch, and without this delegate the grant arrives with nothing listening.
        manager.delegate = self

        // The whole point of the probe is the wake, and a wake means a NEW process with `armed`
        // back to false. Re-anchoring here would move all four rings to wherever the wake happened
        // and every capture would measure a fresh set of circles that nobody ever walked out of.
        // A stored anchor therefore means "already armed", and this launch only reports.
        if let stored = Self.storedAnchor() {
            anchor = stored.coordinate
            armedAt = stored.armedAt
            armed = true
            reportResumed()
            return
        }

        requestAnchorFix()
    }

    /// Ends the capture and clears the anchor, so the next enabled launch arms a fresh set.
    ///
    /// Region monitoring survives process death: the OS keeps relaunching the app for these rings
    /// until something stops them, so turning the probe off has to turn the registration off too.
    /// Only an explicit disable reaches here — a launch that merely reads `false` (including an
    /// unreadable defaults domain before first unlock) must leave a running capture alone.
    func stop() {
        var removed = 0
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.identifierPrefix) {
            manager.stopMonitoring(for: region)
            removed += 1
        }
        Self.clearStoredAnchor()
        armed = false
        anchor = nil
        armedAt = nil
        anchorAttempts = 0
        DiagnosticLog.shared.note(
            "Region radius probe stopped"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.stopped io=obs rings=\(removed)",
            level: .info
        )
    }

    // MARK: - Arming

    private func requestAnchorFix() {
        guard !armed, anchorAttempts < Self.maxAnchorAttempts else { return }
        guard manager.authorizationStatus == .authorizedAlways else {
            // Not a failure: the SDK prompts after launch, and
            // `locationManagerDidChangeAuthorization` retries when the grant lands.
            DiagnosticLog.shared.note(
                "Region radius probe waiting for Always authorization"
                    + DiagnosticLog.delimiter
                    + "ev=probe.radius.skipped io=obs why=not_always"
                    + " status=\(manager.authorizationStatus.rawValue)",
                level: .info
            )
            return
        }
        anchorAttempts += 1
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()
    }

    /// Anchors the rings on a real fix rather than a cached one. An anchor taken from a stale or
    /// coarse position puts every ring in the wrong place and the whole capture measures nothing.
    private func arm(at coordinate: CLLocationCoordinate2D, accuracy: CLLocationAccuracy) {
        guard !armed else { return }
        // A fix coarser than the smallest ring cannot place it meaningfully — the ring would sit
        // inside its own uncertainty and any promotion would be noise.
        guard accuracy > 0, accuracy < Self.radii[0] else {
            DiagnosticLog.shared.note(
                "Region radius probe anchor fix too coarse, retrying"
                    + DiagnosticLog.delimiter
                    + "ev=probe.radius.skipped io=obs why=anchor_too_coarse"
                    + " acc=\(fmt(accuracy, 1)) try=\(anchorAttempts)/\(Self.maxAnchorAttempts)",
                level: .info
            )
            requestAnchorFix()
            return
        }
        armed = true
        anchor = coordinate
        armedAt = Date()
        Self.storeAnchor(coordinate: coordinate, armedAt: armedAt ?? Date())
        for radius in Self.radii {
            let region = CLCircularRegion(
                center: coordinate,
                radius: radius,
                identifier: identifier(for: radius)
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        DiagnosticLog.shared.note(
            "Region radius probe armed on \(Self.radii.count) rings"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.armed io=obs"
                + " lat=\(fmt(coordinate.latitude, 6)) lon=\(fmt(coordinate.longitude, 6))"
                + " acc=\(fmt(accuracy, 1)) try=\(anchorAttempts)"
                + " radii=\(Self.radii.map { String(Int($0)) }.joined(separator: "_"))",
            level: .info
        )
        requestStateForAllRings()
    }

    /// Reports what survived the relaunch before asking the OS what it believes.
    ///
    /// A ring the OS silently dropped and a ring it kept but never promotes produce the same
    /// silence in the log, and only this count separates them.
    private func reportResumed() {
        let surviving = manager.monitoredRegions
            .compactMap { $0 as? CLCircularRegion }
            .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
            .map { Int($0.radius) }
            .sorted()
        DiagnosticLog.shared.note(
            "Region radius probe resumed on an existing anchor"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.resumed io=obs"
                + " rings=\(surviving.count)/\(Self.radii.count)"
                + " alive=\(surviving.map(String.init).joined(separator: "_"))"
                + " since=\(fmt(armedAt.map { Date().timeIntervalSince($0) } ?? -1, 1))"
                + " launch=\(launchedByLocation ? "location" : "app_start")",
            level: .info
        )
        requestStateForAllRings()
    }

    /// Asks the OS which rings it currently considers us inside.
    ///
    /// This is the measurement's second, independent channel. A crossing needs the user to walk;
    /// a state query needs nothing, and it answers the same question — the OS reporting `outside`
    /// for the 25 m ring while the device stands at its centre says that radius is not honoured,
    /// with no field trip required.
    private func requestStateForAllRings() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.identifierPrefix) {
            manager.requestState(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DiagnosticLog.shared.note(
            "Region radius probe saw authorization \(manager.authorizationStatus.rawValue)"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.auth io=obs status=\(manager.authorizationStatus.rawValue)"
                + " armed=\(armed)",
            level: .info
        )
        // The grant usually lands after launch, which is the one chance to arm this capture.
        guard !armed else { return }
        // Reset the budget: attempts spent while unauthorized were never going to succeed, and
        // counting them would let a late grant find the probe already given up.
        anchorAttempts = 0
        requestAnchorFix()
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        arm(at: fix.coordinate, accuracy: fix.horizontalAccuracy)
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        DiagnosticLog.shared.note(
            "Region radius probe could not obtain an anchor fix"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.skipped io=obs why=anchor_failed"
                + " err=\((error as NSError).code) try=\(anchorAttempts)/\(Self.maxAnchorAttempts)",
            level: .info
        )
        requestAnchorFix()
    }

    func locationManager(_: CLLocationManager, didEnterRegion region: CLRegion) {
        report(region, transition: "enter")
    }

    func locationManager(_: CLLocationManager, didExitRegion region: CLRegion) {
        report(region, transition: "exit")
    }

    func locationManager(_: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier.hasPrefix(Self.identifierPrefix) else { return }
        let token: String
        switch state {
        case .inside: token = "inside"
        case .outside: token = "outside"
        case .unknown: token = "unknown"
        @unknown default: token = "unhandled"
        }
        DiagnosticLog.shared.note(
            "Region radius probe state for \(region.identifier) is \(token)"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.state io=in id=\(region.identifier)"
                + " rad=\(fmt((region as? CLCircularRegion)?.radius ?? -1, 0))"
                + " state=\(token) off=\(fmt(offsetFromAnchor(), 1))",
            level: .info
        )
    }

    func locationManager(_: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier, identifier.hasPrefix(Self.identifierPrefix) else { return }
        // A radius the OS refuses outright is a different answer from one it accepts and never
        // promotes, and only this callback distinguishes them.
        DiagnosticLog.shared.note(
            "Region radius probe monitoring failed for \(identifier)"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.failed io=in id=\(identifier) err=\((error as NSError).code)",
            level: .info
        )
    }

    // MARK: - Reporting

    private func report(_ region: CLRegion, transition: String) {
        guard region.identifier.hasPrefix(Self.identifierPrefix) else { return }
        let radius = (region as? CLCircularRegion)?.radius ?? -1
        let fix = manager.location
        DiagnosticLog.shared.note(
            "Region radius probe \(transition) on \(Int(radius)) m ring"
                + DiagnosticLog.delimiter
                + "ev=probe.radius.\(transition) io=in"
                + " id=\(region.identifier) rad=\(fmt(radius, 0))"
                // Distance from the anchor at the moment of the callback, against the ring the OS
                // claims was crossed. A promotion reported far from its own radius is a LATE
                // promotion, which is the difference between "this radius works" and "this radius
                // eventually works" — the number the wake decision actually turns on.
                + " off=\(fmt(offsetFromAnchor(), 1))"
                + " acc=\(fmt(fix?.horizontalAccuracy ?? -1, 1))"
                + " since=\(fmt(armedAt.map { Date().timeIntervalSince($0) } ?? -1, 1))"
                + " state=\(stateToken())"
                + " launch=\(launchedByLocation ? "location" : "app_start")",
            level: .info
        )
    }

    /// Distance from the armed anchor to the manager's current fix, or -1 when either is missing.
    private func offsetFromAnchor() -> Double {
        guard let anchor, let fix = manager.location else { return -1 }
        return CLLocation(latitude: anchor.latitude, longitude: anchor.longitude).distance(from: fix)
    }

    private func identifier(for radius: Double) -> String {
        "\(Self.identifierPrefix)\(Int(radius))"
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
        String(format: "%.\(places)f", value)
    }
}
