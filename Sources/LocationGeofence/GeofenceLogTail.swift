import CioInternalCommon
import CoreLocation
import Foundation

/// Whether a record is something the SDK was told, something the SDK decided, or neither.
///
/// Stated explicitly rather than inferred from the event name: replay feeds the `in` records back
/// and compares the `out` records, so a naming convention getting this wrong invalidates a run.
enum GeofenceLogIO: String {
    case input = "in"
    case output = "out"
    case observation = "obs"
}

/// Whether the SDK emits the diagnostic tail.
///
/// Read from the host app's `Info.plist`, deliberately not from an API. `CioInternalCommon` ships
/// as a CocoaPods module on every app that takes a Customer.io pod, so anything public there is
/// reachable from a customer app — including via React Native and Flutter. An Info.plist key is
/// not importable and cannot be set by a dependency.
enum GeofenceDiagnostics {
    static let infoPlistKey = "CIOGeofenceDiagnostics"

    private static let gate = DiagnosticsGate()

    static var isEnabled: Bool { gate.isEnabled }

    /// True exactly once per enablement, so the warning does not repeat on every record.
    static func claimWarning() -> Bool {
        gate.claimWarning()
    }

    /// Test hook; `nil` restores the Info.plist value.
    static func setEnabledForTesting(_ value: Bool?) {
        gate.setOverride(value)
    }
}

private final class DiagnosticsGate: @unchecked Sendable {
    private let lock = NSLock()
    private var override: Bool?
    private var warned = false
    private lazy var fromBundle: Bool =
        (Bundle.main.object(forInfoDictionaryKey: GeofenceDiagnostics.infoPlistKey) as? Bool) ?? false

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return override ?? fromBundle
    }

    func setOverride(_ value: Bool?) {
        lock.lock()
        defer { lock.unlock() }
        override = value
        warned = false
    }

    func claimWarning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !warned else { return false }
        warned = true
        return true
    }
}

/// Builds the machine-readable tail appended to a geofence log message.
///
/// Existing prose is unchanged; the machine detail rides behind a ` || ` delimiter as flat
/// `key=value` pairs. Records added by this work emit their prose either way — only the tail
/// is gated.
///
/// ```
/// [Geofence] Tracked enter event for geofence notl_core || ev=transition.emitted io=out id=notl_core t=enter
/// ```
enum GeofenceLog {
    /// Chosen over a single pipe after confirming no log message on either platform contains one.
    /// A parser splits on the **last** occurrence and only accepts the remainder as a tail if it
    /// parses cleanly as `key=value` pairs, so prose that someday contains `||` stays prose.
    static let delimiter = " || "

    /// The single gate for every diagnostic value; returns nothing when diagnostics are off.
    ///
    /// - Parameters:
    ///   - ev: stable machine key. Never reworded — `msg` is the prose someone will rewrite.
    ///   - io: replay classification.
    ///   - fields: an autoclosure, so distance maps and id lists cost nothing when off. `nil`
    ///     values are omitted, keeping absent and empty distinct.
    static func tail(
        _ ev: String,
        _ io: GeofenceLogIO,
        _ fields: @autoclosure () -> [(String, String?)] = [],
        logger: Logger? = nil
    ) -> String {
        guard GeofenceDiagnostics.isEnabled else { return "" }
        if let logger, GeofenceDiagnostics.claimWarning() {
            logger.error(
                "Diagnostics: internal geofence diagnostics are ENABLED. Logs now carry machine-readable detail including device coordinates. This is intended for Customer.io field testing and must not be enabled in a production build.",
                "Geofence",
                nil
            )
        }

        var parts = ["ev=\(ev)", "io=\(io.rawValue)"]
        for (key, value) in fields() {
            guard let value else { continue }
            parts.append("\(key)=\(sanitize(value))")
        }
        return delimiter + parts.joined(separator: " ")
    }

    /// Values may not contain whitespace — the parser splits the tail on it. Geofence identifiers
    /// come from workspace configuration and can contain anything at all, so they are folded here
    /// rather than trusted.
    static func sanitize(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for character in value {
            out.append(character.isWhitespace ? "_" : character)
        }
        return out.isEmpty ? "_" : out
    }

    // MARK: - Value formatting

    static func num(_ value: Double?, _ places: Int = 1) -> String? {
        guard let value, value.isFinite else { return nil }
        return String(format: "%.\(places)f", value)
    }

    static func int(_ value: Int?) -> String? {
        value.map(String.init)
    }

    static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Monotonic seconds for measuring durations.
    ///
    /// Wall clock can step under NTP mid-measurement and yield a negative `ms=`. `CLOCK_MONOTONIC`
    /// counts through sleep, which is what makes it comparable with Android's `elapsedRealtime()` —
    /// the two platforms have to mean the same thing by `ms=` for one parser to read both.
    static func monotonicNow() -> TimeInterval {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1000000000
    }

    /// A comma-separated list, no spaces. Used for registered identifiers and ranking results.
    ///
    /// Capped because a ranked list of every candidate on a dense workspace would dwarf the record
    /// it is attached to. The count travels separately, so a truncated list is still honest about
    /// how much it left out.
    static func list(_ values: [String], limit: Int = 25) -> String? {
        guard !values.isEmpty else { return nil }
        let head = values.prefix(limit).map(sanitize).joined(separator: ",")
        return values.count > limit ? "\(head),+\(values.count - limit)" : head
    }

    /// Folds arbitrary text into a snake_case token.
    ///
    /// Reasons are tokens, never prose: `why=no_identified_user` survives someone rewriting the
    /// sentence in front of it, and `why=no identified user` would break the parser on the first
    /// space anyway.
    static func token(_ value: String) -> String {
        var out = ""
        var lastWasSeparator = false
        for character in value.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator, !out.isEmpty {
                out.append("_")
                lastWasSeparator = true
            }
        }
        while out.hasSuffix("_") {
            out.removeLast()
        }
        return out.isEmpty ? "unknown" : out
    }

    /// Permission tier as a stable token rather than the raw enum ordinal, which means nothing to
    /// anyone reading a log a month later.
    static func permission(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "when_in_use"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Fix quality and provenance (ungated)

    /// Where a fix came from. Trustworthiness differs enormously between these, and until now the
    /// log said only that *a* position existed.
    enum FixSource: String {
        /// `CLLocationManager.location` — the OS's cached fix. Can freeze at process start on a
        /// long-suspended process, so this is the one that silently goes stale.
        case managerCache = "manager_cache"
        /// The freshest fix `MovementFixResolver` has seen delivered.
        case resolver
        /// Requested on purpose for this event and waited for.
        case freshRequest = "fresh_request"
        /// The contradiction gate's fix, taken inside a re-add replay window.
        case gate
        /// A synthesized transition, not an OS-delivered one.
        case synthetic
        case none
    }

    /// How good the fix is and where it came from.
    ///
    /// `age` is the one to notice: `bestKnownFix()` can return a fix that is hours old on a
    /// long-suspended process, and an overshoot distance computed from one of those looks identical
    /// to a real measurement without it.
    ///
    /// Like everything else in the tail, these reach a log only when diagnostics are enabled — the
    /// gate lives in `tail(_:_:_:logger:)`, so nothing here needs its own check.
    static func fixQuality(_ location: CLLocation?, source: FixSource) -> [(String, String?)] {
        var fields: [(String, String?)] = [("fixsrc", source.rawValue)]
        guard let location else { return fields }

        fields.append(("acc", num(location.horizontalAccuracy)))
        fields.append(("age", num(-location.timestamp.timeIntervalSinceNow)))
        if location.verticalAccuracy > 0 {
            fields.append(("vacc", num(location.verticalAccuracy)))
        }
        // Marks a fix injected by `devicectl simulate location` or Xcode. Without it a bench run
        // and a real drive are indistinguishable once the files are pooled, which is exactly the
        // sort of contamination nobody notices until a conclusion is already built on it.
        if #available(iOS 15.0, *), let info = location.sourceInformation {
            fields.append(("sim", bool(info.isSimulatedBySoftware)))
            if info.isProducedByAccessory {
                fields.append(("accessory", "true"))
            }
        }
        return fields
    }

    /// How long an OS-dated event waited before the SDK processed it.
    ///
    /// `CLMonitor` stamps each event with the date the daemon decided it. An event can then sit in
    /// `pendingEvents` until bootstrap binds a handler, so a "late" crossing may have been observed
    /// on time and delivered late — two very different faults that currently look the same.
    static func eventTiming(_ eventDate: Date?) -> [(String, String?)] {
        guard let eventDate else { return [] }
        return [("evage", num(-eventDate.timeIntervalSinceNow))]
    }

    // MARK: - Device position

    /// Device position.
    ///
    /// No separate switch: a single gate over the whole tail is what makes "customer builds see
    /// exactly what they saw before" a claim you can check in one assertion, instead of a set of
    /// per-field arguments a reviewer has to accept one at a time.
    static func position(_ location: CLLocation?) -> [(String, String?)] {
        guard let location else { return [] }
        return [
            ("lat", num(location.coordinate.latitude, 5)),
            ("lon", num(location.coordinate.longitude, 5)),
            ("alt", num(location.altitude, 1)),
            ("spd", location.speed >= 0 ? num(location.speed) : nil),
            ("brg", location.course >= 0 ? num(location.course) : nil)
        ]
    }

    /// Coordinates only, for the paths that carry `LocationData` rather than a full fix.
    static func position(_ location: LocationData?) -> [(String, String?)] {
        guard let location else { return [] }
        return [
            ("lat", num(location.latitude, 5)),
            ("lon", num(location.longitude, 5))
        ]
    }
}

extension Logger {
    /// Routes every call site through the gate with `self`, so the one-time "diagnostics are
    /// enabled" warning reaches the host app's own logger.
    func geofenceTail(
        _ ev: String,
        _ io: GeofenceLogIO,
        _ fields: @autoclosure () -> [(String, String?)] = []
    ) -> String {
        GeofenceLog.tail(ev, io, fields(), logger: self)
    }
}
