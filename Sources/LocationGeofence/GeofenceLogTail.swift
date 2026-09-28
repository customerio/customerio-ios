import CioInternalCommon
import CoreLocation
import Foundation

/// Replay feeds `in` records back and compares `out` records.
enum GeofenceLogIO: String {
    case input = "in"
    case output = "out"
    case observation = "obs"
}

/// An `Info.plist` key, not an API: anything public in `CioInternalCommon` is reachable from
/// customer apps.
enum GeofenceDiagnostics {
    static let infoPlistKey = "CIOGeofenceDiagnostics"

    private static let gate = DiagnosticsGate()

    /// Task-local so concurrent test suites can't see each other's value.
    @TaskLocal static var overrideForTesting: Bool?

    static var isEnabled: Bool { overrideForTesting ?? gate.isEnabled }
}

/// `@unchecked Sendable`: the lazy value is only read under `lock`.
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

/// Only the tail is gated; the prose is emitted regardless, except records behind their own
/// `GeofenceDiagnostics.isEnabled` guard.
///
/// ```
/// [Geofence] Accepted enter for geofence notl_core, queued 1 row(s) || ev=transition.accepted io=out id=notl_core t=enter n=1
/// ```
enum GeofenceLog {
    /// A parser splits on the **last** occurrence, and only if the remainder is all `key=value`.
    static let delimiter = " || "

    enum RemovalOp: String {
        case readd
        case drop
    }

    /// `ev` is a stable machine key: never reword it. `nil` field values are omitted, keeping absent
    /// and empty distinct.
    static func tail(
        _ ev: String,
        _ io: GeofenceLogIO,
        _ fields: @autoclosure () -> [(String, String?)] = []
    ) -> String {
        guard GeofenceDiagnostics.isEnabled else { return "" }
        var parts = ["ev=\(ev)", "io=\(io.rawValue)"]
        for (key, value) in fields() {
            guard let value else { continue }
            let safe = composedKeys.contains(key) ? foldWhitespace(value) : sanitize(value)
            parts.append("\(key)=\(safe)")
        }
        return delimiter + parts.joined(separator: " ")
    }

    /// Folded out of untrusted values (workspace ids can contain anything), never out of composed ones.
    static let separators: Set<Character> = ["=", ",", ":", "|"]

    /// Values that contain separators on purpose.
    private static let composedKeys: Set<String> = [
        "ranked", "evicted", "ids", "gs", "tt", "ring", "missing", "extra"
    ]

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

    /// Not wall clock, which can step and yield a negative `ms=`. Counts through sleep, like Android's
    /// `elapsedRealtime()`.
    static func monotonicNow() -> TimeInterval {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1000000000
    }

    /// Not sanitized: callers must sanitize the untrusted part before composing.
    static func composedList(_ values: [String], limit: Int = 25) -> String? {
        guard !values.isEmpty else { return nil }
        let head = values.prefix(max(0, limit)).joined(separator: ",")
        return values.count > limit ? "\(head),+\(values.count - limit)" : head
    }

    static func list(_ values: [String], limit: Int = 25) -> String? {
        guard !values.isEmpty else { return nil }
        // `prefix` traps on a negative length; a log must never crash the process.
        let head = values.prefix(max(0, limit)).map(sanitize).joined(separator: ",")
        return values.count > limit ? "\(head),+\(values.count - limit)" : head
    }

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

    enum FixSource: String, CaseIterable {
        /// `CLLocationManager.location`; can be frozen at process start after a long suspension.
        case managerCache = "manager_cache"
        /// The freshest fix `MovementFixResolver` has seen delivered.
        case resolver
        case freshRequest = "fresh_request"
        /// The contradiction gate's fix.
        case gate
        /// Delivered by the Location module: an arrival, not a read.
        case bus
        /// A synthesized transition, not an OS-delivered one.
        case synthetic
        case none
    }

    static func fixQuality(_ location: CLLocation?, source: FixSource, now: Date) -> [(String, String?)] {
        var fields: [(String, String?)] = [("fixsrc", source.rawValue)]
        guard let location else { return fields }

        fields.append(("acc", num(location.horizontalAccuracy)))
        fields.append(("age", num(now.timeIntervalSince(location.timestamp), 6)))
        if location.verticalAccuracy > 0 {
            fields.append(("vacc", num(location.verticalAccuracy)))
        }
        if #available(iOS 15.0, *), let info = location.sourceInformation {
            fields.append(("sim", bool(info.isSimulatedBySoftware)))
            if info.isProducedByAccessory {
                fields.append(("accessory", "true"))
            }
        }
        return fields
    }

    static func eventTiming(_ eventDate: Date?, now: Date) -> [(String, String?)] {
        guard let eventDate else { return [] }
        return [
            ("evage", num(now.timeIntervalSince(eventDate), 6)),
            // Unrounded: the only field that identifies a re-delivered event.
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

extension GeofenceMonitorEventOutcome {
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
