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
/// Read from the host app's `Info.plist`, not from an API: `CioInternalCommon` ships as a
/// CocoaPods module on every app taking a Customer.io pod, so anything public there is reachable
/// from a customer app. An Info.plist key is not importable and cannot be set by a dependency.
enum GeofenceDiagnostics {
    static let infoPlistKey = "CIOGeofenceDiagnostics"

    private static let gate = DiagnosticsGate()

    /// Test-only. The one concession to testability in this file; production reads the bundle.
    static var overrideForTesting: Bool?

    static var isEnabled: Bool { overrideForTesting ?? gate.isEnabled }
}

private final class DiagnosticsGate: @unchecked Sendable {
    private let lock = NSLock()
    private lazy var fromBundle: Bool =
        (Bundle.main.object(forInfoDictionaryKey: GeofenceDiagnostics.infoPlistKey) as? Bool) ?? false

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fromBundle
    }
}

/// Builds the machine-readable tail appended to a geofence log message.
///
/// Existing prose is unchanged. Records added by this work emit prose either way; only the tail
/// is gated.
///
/// ```
/// [Geofence] Tracked enter event for geofence notl_core || ev=transition.emitted io=out id=notl_core t=enter
/// ```
enum GeofenceLog {
    /// A parser splits on the **last** occurrence, and only if the remainder is all `key=value`.
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
        _ fields: @autoclosure () -> [(String, String?)] = []
    ) -> String {
        guard GeofenceDiagnostics.isEnabled else { return "" }
        var parts = ["ev=\(ev)", "io=\(io.rawValue)"]
        for (key, value) in fields() {
            guard let value else { continue }
            // Sanitize by default; the few composed keys opt out. The reverse arrangement left
            // every `id` call site unprotected, because nothing forced a new field to be wrapped.
            let safe = composedKeys.contains(key) ? foldWhitespace(value) : sanitize(value)
            parts.append("\(key)=\(safe)")
        }
        return delimiter + parts.joined(separator: " ")
    }

    /// The parser splits on whitespace, and workspace-authored ids can contain anything.
    /// Every character the format itself uses to separate things. Applied to *untrusted tokens*
    /// only — a workspace-authored id containing one of these would otherwise split a field: `=` a
    /// pair, `,` a list, `:` an `id:distance` entry in `ranked`, `|` the tail delimiter.
    ///
    /// Deliberately not applied to a finished value: `list` and `ranked` compose their separators
    /// on purpose, and folding those turns `a,b` into `a_b`.
    private static let separators: Set<Character> = ["=", ",", ":", "|"]

    /// The only values that compose the format's separators on purpose. Everything else is an
    /// untrusted token — region identifiers are workspace-authored and can hold anything.
    private static let composedKeys: Set<String> = ["ranked", "evicted", "ids"]

    /// Applied to every finished value. Only whitespace, which is what separates one `key=value`
    /// from the next — the value's own structure is already the caller's business.
    static func foldWhitespace(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for character in value {
            out.append(character.isWhitespace ? "_" : character)
        }
        return out.isEmpty ? "_" : out
    }

    static func sanitize(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for character in value {
            out.append(separators.contains(character) || character.isWhitespace ? "_" : character)
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

    /// Monotonic: wall clock can step under NTP and yield a negative `ms=`. `CLOCK_MONOTONIC`
    /// counts through sleep, matching Android's `elapsedRealtime()` so `ms=` means one thing.
    static func monotonicNow() -> TimeInterval {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1000000000
    }

    /// For elements the caller has already composed, like `id:distance` — their structure is
    /// deliberate, so the untrusted part must be sanitized before composing, not after.
    static func composedList(_ values: [String], limit: Int = 25) -> String? {
        guard !values.isEmpty else { return nil }
        let head = values.prefix(max(0, limit)).joined(separator: ",")
        return values.count > limit ? "\(head),+\(values.count - limit)" : head
    }

    /// Comma-separated, capped; the count travels separately so truncation stays honest.
    static func list(_ values: [String], limit: Int = 25) -> String? {
        guard !values.isEmpty else { return nil }
        // `prefix` traps on a negative length; no caller passes one, but a log must not be
        // the thing that takes the process down.
        let head = values.prefix(max(0, limit)).map(sanitize).joined(separator: ",")
        return values.count > limit ? "\(head),+\(values.count - limit)" : head
    }

    /// Reasons are tokens so they survive the sentence in front of them being reworded.
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

    /// A stable token rather than the raw enum ordinal.
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

    /// Where a fix came from; the log previously said only that *a* position existed.
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
    /// `age` is the one to notice: `bestKnownFix()` can be hours old on a long-suspended process,
    /// and an overshoot computed from one of those looks identical to a real measurement.
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

    /// How long an OS-dated event waited before the SDK processed it — "observed late" and
    /// "observed on time, delivered late" are different faults that otherwise look the same.
    static func eventTiming(_ eventDate: Date?) -> [(String, String?)] {
        guard let eventDate else { return [] }
        return [("evage", num(-eventDate.timeIntervalSinceNow))]
    }

    // MARK: - Device position

    /// Device position. Gated with the rest of the tail; no per-field switch.
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
    /// Call-site shim; keeps `GeofenceLog.` off ~40 call sites.
    func geofenceTail(
        _ ev: String,
        _ io: GeofenceLogIO,
        _ fields: @autoclosure () -> [(String, String?)] = []
    ) -> String {
        GeofenceLog.tail(ev, io, fields())
    }
}
