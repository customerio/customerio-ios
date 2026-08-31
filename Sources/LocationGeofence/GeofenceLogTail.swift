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

    /// How good the fix is and where it came from. **Deliberately ungated.**
    ///
    /// None of these keys says anything about *where* the device is, so none of them is the thing
    /// `logPreciseLocation` exists to protect. Gating them would mean a default build cannot judge
    /// whether a transition's position is worth anything at all — and `age` in particular is the
    /// difference between a measurement and a guess: `bestKnownFix()` can return a fix that is
    /// hours old, and an overshoot distance computed from one of those looks identical to a real
    /// one.
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

    /// Device position, emitted only when ``CioDiagnostics/logPreciseLocation`` is on.
    ///
    /// Speed and course are gated alongside the coordinate, not with the quality keys above: a
    /// run of them from a known starting point is dead reckoning, so they carry positional
    /// information even though neither is a coordinate.
    static func position(_ location: CLLocation?, logger: Logger) -> [(String, String?)] {
        guard let location, allowPreciseLocation(logger: logger) else { return [] }
        return [
            ("lat", num(location.coordinate.latitude, 5)),
            ("lon", num(location.coordinate.longitude, 5)),
            ("alt", num(location.altitude, 1)),
            ("spd", location.speed >= 0 ? num(location.speed) : nil),
            ("brg", location.course >= 0 ? num(location.course) : nil)
        ]
    }

    /// Coordinates only, for the paths that carry `LocationData` rather than a full fix.
    static func position(_ location: LocationData?, logger: Logger) -> [(String, String?)] {
        guard let location, allowPreciseLocation(logger: logger) else { return [] }
        return [
            ("lat", num(location.latitude, 5)),
            ("lon", num(location.longitude, 5))
        ]
    }
}
