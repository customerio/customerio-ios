import Foundation

/// Switch for the SDK's internal diagnostic instrumentation.
///
/// Not part of the public SDK surface. `CioInternalCommon` is only exposed as a package product
/// when the `CI` environment variable is set, so nothing here appears in a host app's autocomplete
/// or documentation — it is reachable by our own sample apps and tests and nowhere else.
public enum CioDiagnostics {
    private static let state = DiagnosticsState()

    /// Whether the SDK emits machine-readable diagnostic detail alongside its human-readable logs.
    ///
    /// **Default `false`, and it must stay that way.**
    ///
    /// This is an audience switch, not a privacy classifier. The `| key=value` tail the geofence
    /// logger appends exists for one consumer: our own off-device test harness. No customer reads
    /// it, no customer needs it, and no product behaviour depends on it. So the question for any
    /// given field is not "is this one sensitive enough to hide" — it is "did we ask for this
    /// output here", and in a customer's app the answer is always no.
    ///
    /// Framing it that way is what makes the guarantee checkable in one line rather than field by
    /// field: **with this off, the SDK's log output is byte-identical to what it was before the
    /// diagnostics work.** A host app that ships with debug logging left on — the case this
    /// protects — sees exactly the prose it saw before, and gains nothing new to leak into a crash
    /// reporter or log aggregator.
    ///
    /// It also means a field added to the tail later needs no privacy review of its own. The
    /// alternative, deciding per field whether it reveals position, gets the easy calls right and
    /// then quietly gets one wrong.
    ///
    /// Turning anything on therefore takes two deliberate actions — this flag set *and* the log
    /// level at `.debug`, which is not the default.
    public static var enabled: Bool {
        get { state.enabled }
        set { state.enabled = newValue }
    }

    /// Claims the right to log the "diagnostics enabled" warning, returning `true` exactly once
    /// per enablement.
    ///
    /// `public` only because the caller lives in another module (`CioLocationGeofence`); like the
    /// rest of this type it is not reachable from a host app.
    public static func claimEnabledWarning() -> Bool {
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
