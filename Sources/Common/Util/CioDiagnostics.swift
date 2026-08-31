import Foundation

/// Internal diagnostics switches.
///
/// Not part of the public SDK surface. `CioInternalCommon` is only exposed as a package product
/// when the `CI` environment variable is set, so nothing here appears in a host app's autocomplete
/// or documentation — it is reachable by our own sample apps and tests and nowhere else.
public enum CioDiagnostics {
    private static let state = DiagnosticsState()

    /// Whether geofence diagnostics may include the device's precise position.
    ///
    /// **Default `false`, and it must stay that way.**
    ///
    /// Geofence logs carry a lot that is safe at debug level — region identifiers, transition
    /// types, counts, ranking positions, reasons, durations. Precise coordinates are different in
    /// kind. "User entered geofence X" reveals coarse location and is inherent to the feature; it
    /// is what the SDK already reports to the backend. A latitude and longitude to five decimal
    /// places is strictly extra, and it is what a host app would leak if it shipped with debug
    /// logging left on and a crash reporter or log aggregator capturing console output.
    ///
    /// Gates `lat`, `lon`, `acc`, `spd` and `brg` only. Region geometry (`rlat`, `rlon`, `rad`)
    /// stays on: it is workspace configuration rather than user data, and the geofence identifier
    /// already carries the same information for anyone holding that configuration.
    ///
    /// Leaking anything therefore takes two deliberate actions — this flag set *and* the log level
    /// at `.debug`, which is not the default.
    public static var logPreciseLocation: Bool {
        get { state.enabled }
        set { state.enabled = newValue }
    }

    /// Claims the right to log the "precise location is enabled" warning, returning `true` exactly
    /// once per enablement.
    ///
    /// `public` only because the caller lives in another module (`CioLocationGeofence`); like the
    /// rest of this type it is not reachable from a host app.
    public static func claimPreciseLocationWarning() -> Bool {
        state.claimWarning()
    }
}

private final class DiagnosticsState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var warned = false

    var enabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
            // Re-arm the warning so a host app that toggles the flag back on is told again.
            if !newValue {
                warned = false
            }
        }
    }

    func claimWarning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !warned else { return false }
        warned = true
        return true
    }
}
