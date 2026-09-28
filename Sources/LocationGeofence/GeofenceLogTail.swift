import CioInternalCommon
import CoreLocation
import Foundation

/// Whether a record is something the SDK was told, something it decided, or neither. Explicit
/// rather than inferred from the name: replay feeds `in` records back and compares `out` records.
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

    /// Test-only. Task-local so concurrently running suites cannot observe each other's value.
    @TaskLocal static var overrideForTesting: Bool?

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

/// Builds the machine-readable tail appended to a geofence log message. Only the tail is gated;
/// the prose is emitted regardless, except on the few records gated whole.
///
/// ```
/// [Geofence] Accepted enter for geofence notl_core, queued 1 row(s) || ev=transition.accepted io=out id=notl_core t=enter n=1
/// ```
enum GeofenceLog {
    /// A parser splits on the **last** occurrence, and only if the remainder is all `key=value`.
    static let delimiter = " || "

    /// Why a condition was removed from `CLMonitor`, on `condition.removed`. An enum so call sites
    /// can't introduce a third spelling.
    enum RemovalOp: String {
        /// Clearing the way for an immediate re-add of the same identifier.
        case readd
        /// The condition is leaving the registered set.
        case drop
    }

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
            // Sanitize by default so a new field can't forget to; composed keys opt out.
            let safe = composedKeys.contains(key) ? foldWhitespace(value) : sanitize(value)
            parts.append("\(key)=\(safe)")
        }
        return delimiter + parts.joined(separator: " ")
    }

    /// Characters the format uses as separators: `=` a pair, `,` a list, `:` an `id:distance` entry
    /// in `ranked`, `|` the tail delimiter. Folded out of untrusted tokens (workspace-authored ids
    /// can contain anything), never out of a composed value, where `a,b` must not become `a_b`.
    static let separators: Set<Character> = ["=", ",", ":", "|"]

    /// Values that compose the format's separators on purpose. Everything else is untrusted.
    private static let composedKeys: Set<String> = [
        "ranked", "evicted", "ids", "gs", "tt", "ring", "missing", "extra"
    ]

    /// Used instead of `sanitize` for composed values: folds only whitespace, which separates one
    /// `key=value` from the next.
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
        // `prefix` traps on a negative length; a log must never crash the process.
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

    /// Where a fix came from.
    enum FixSource: String, CaseIterable {
        /// `CLLocationManager.location` — the OS's cached fix. Can freeze at process start on a
        /// long-suspended process, so this is the one that silently goes stale.
        case managerCache = "manager_cache"
        /// The freshest fix `MovementFixResolver` has seen delivered.
        case resolver
        /// Requested on purpose for this event and waited for.
        case freshRequest = "fresh_request"
        /// The contradiction gate's fix, taken inside a re-add replay window.
        case gate
        /// Delivered by the Location module: an arrival, not a read. Matches Android's `prov=bus`.
        case bus
        /// A synthesized transition, not an OS-delivered one.
        case synthetic
        case none
    }

    /// How good the fix is and where it came from. `age` matters most: `bestKnownFix()` can be
    /// hours old on a long-suspended process.
    static func fixQuality(_ location: CLLocation?, source: FixSource, now: Date) -> [(String, String?)] {
        var fields: [(String, String?)] = [("fixsrc", source.rawValue)]
        guard let location else { return fields }

        fields.append(("acc", num(location.horizontalAccuracy)))
        fields.append(("age", num(now.timeIntervalSince(location.timestamp), 6)))
        if location.verticalAccuracy > 0 {
            fields.append(("vacc", num(location.verticalAccuracy)))
        }
        // Marks a fix injected by `devicectl simulate location` or Xcode, so bench runs and real
        // drives stay distinguishable once captures are pooled.
        if #available(iOS 15.0, *), let info = location.sourceInformation {
            fields.append(("sim", bool(info.isSimulatedBySoftware)))
            if info.isProducedByAccessory {
                fields.append(("accessory", "true"))
            }
        }
        return fields
    }

    /// How long an OS-dated event waited before the SDK processed it, separating "observed late"
    /// from "observed on time, delivered late".
    static func eventTiming(_ eventDate: Date?, now: Date) -> [(String, String?)] {
        guard let eventDate else { return [] }
        return [
            ("evage", num(now.timeIntervalSince(eventDate), 6)),
            // Absolute and unrounded: the only field that identifies a re-delivered event.
            ("edate", num(eventDate.timeIntervalSince1970, 6))
        ]
    }

    // MARK: - Device position

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
    func geofenceTail(
        _ ev: String,
        _ io: GeofenceLogIO,
        _ fields: @autoclosure () -> [(String, String?)] = []
    ) -> String {
        GeofenceLog.tail(ev, io, fields())
    }
}

/// Lives with the tail rather than with the type: the token is a log contract.
extension GeofenceMonitorEventOutcome {
    /// Stable token for the diagnostic tail, so each suppression is distinguishable from the
    /// others and from the OS never delivering at all.
    var diagnosticReason: String? {
        switch self {
        case .deliver: return nil
        case .suppressedNoChange: return "no_state_change"
        case .suppressedFilteredType: return "transition_type_not_registered"
        case .suppressedNoBaseline: return "baseline_established"
        case .suppressedNewerBaseline: return "newer_baseline"
        case .suppressedRedelivery: return "redelivered"
        case .suppressedPredatesRegistration: return "predates_registration"
        }
    }
}
