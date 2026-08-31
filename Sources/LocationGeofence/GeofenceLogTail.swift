import CioInternalCommon
import CoreLocation
import Foundation

/// Whether a record is something the SDK was told, something the SDK decided, or neither.
///
/// Stated explicitly on every record rather than inferred from the event name. Replay feeds the
/// `in` records back and compares the `out` records that come out the other side, so getting this
/// wrong silently invalidates a whole replay run — and inferring it from a naming convention is
/// exactly the kind of rule that goes wrong quietly a year later.
enum GeofenceLogIO: String {
    /// Crosses into the SDK: an OS callback, a location fix, a lifecycle or permission change, or
    /// the response to a nearby-geofence fetch.
    case input = "in"
    /// Produced by the SDK: emissions and decisions, including registration results and rankings.
    case output = "out"
    /// Neither. Device state, preflight checks, and anything a reference app contributes.
    case observation = "obs"
}

/// Builds the machine-readable tail appended to a geofence log message.
///
/// The human prose in front of the tail stays byte-identical to what it was before enrichment, so
/// nothing regresses for anyone reading Logcat or the Xcode console. Everything a script needs
/// rides behind a ` || ` delimiter as flat `key=value` pairs:
///
/// ```
/// [Geofence] Tracked enter event for geofence notl_core || ev=transition.emitted io=out id=notl_core t=enter
/// ```
///
/// Deliberately *not* a structured logging API. Adding a payload type to the core `Logger` would
/// be a tracked public-API change on both platforms, with a permanent obligation to populate two
/// representations at every call site, and the only consumer is our own tooling.
enum GeofenceLog {
    /// Chosen over a single pipe after confirming no log message on either platform contains one.
    /// A parser splits on the **last** occurrence and only accepts the remainder as a tail if it
    /// parses cleanly as `key=value` pairs, so prose that someday contains `||` stays prose.
    static let delimiter = " || "

    /// - Parameters:
    ///   - ev: stable machine key from the event taxonomy. Never reworded — `msg` is the prose that
    ///     someone will eventually rewrite, `ev` is the contract.
    ///   - io: replay classification.
    ///   - fields: ordered key/value pairs. `nil` values are omitted rather than written as empty,
    ///     so absent and empty stay distinguishable.
    static func tail(_ ev: String, _ io: GeofenceLogIO, _ fields: [(String, String?)] = []) -> String {
        var parts = ["ev=\(ev)", "io=\(io.rawValue)"]
        for (key, value) in fields {
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

    // MARK: - Gated device position

    /// Whether the caller may include device coordinates, warning loudly the first time it may.
    ///
    /// The warning is an error-level log so it survives in a host app's own console even at a
    /// restrictive log level: if this somehow ships enabled, the app's owner is told.
    private static func allowPreciseLocation(logger: Logger) -> Bool {
        guard CioDiagnostics.logPreciseLocation else { return false }
        if CioDiagnostics.claimPreciseLocationWarning() {
            logger.error(
                "Diagnostics: precise location logging is ENABLED. Geofence debug logs now contain device coordinates. This is intended for Customer.io field testing and must not be enabled in a production build.",
                "Geofence",
                nil
            )
        }
        return true
    }

    /// Full device position, emitted only when ``CioDiagnostics/logPreciseLocation`` is on.
    ///
    /// These are the keys that make overshoot distance computable — how far past the boundary the
    /// device actually was when the OS finally reported the crossing — and also the only genuinely
    /// sensitive thing in the record. Hence the switch.
    static func position(_ location: CLLocation?, logger: Logger) -> [(String, String?)] {
        guard let location, allowPreciseLocation(logger: logger) else { return [] }
        return [
            ("lat", num(location.coordinate.latitude, 5)),
            ("lon", num(location.coordinate.longitude, 5)),
            ("acc", num(location.horizontalAccuracy)),
            ("spd", location.speed >= 0 ? num(location.speed) : nil),
            ("brg", location.course >= 0 ? num(location.course) : nil),
            ("age", num(-location.timestamp.timeIntervalSinceNow))
        ]
    }

    /// Coordinates only.
    ///
    /// `LocationData` is what the OS transition callback carries, and it holds latitude and
    /// longitude and nothing else — **no accuracy**. Accuracy on a transition is the single most
    /// useful number for judging a late crossing, and getting it here means threading `CLLocation`
    /// through `GeofenceTransitionHandler`, which is a behavioural change rather than a logging
    /// one. Recorded as a known gap rather than smuggled into this PR.
    static func position(_ location: LocationData?, logger: Logger) -> [(String, String?)] {
        guard let location, allowPreciseLocation(logger: logger) else { return [] }
        return [
            ("lat", num(location.latitude, 5)),
            ("lon", num(location.longitude, 5))
        ]
    }
}
