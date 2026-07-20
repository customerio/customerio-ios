import Foundation

// TESTING-ONLY (geofence-testing branch) — must not merge to feature/main.
/// Process-wide sink the sample app registers so every `Logger.geofenceDebug` line also surfaces
/// as an on-device notification — OS registration, enter/exit callbacks, cold-wake bootstrap, and
/// per-transition outcomes become visible without pulling the log file. Mirrors Android's
/// `GeofenceTestHooks`.
public enum GeofenceTestHooks {
    /// Set by the sample app. Invoked for every geofence debug line, on the SDK's calling thread —
    /// the handler must hop to main before touching UI/notifications.
    public nonisolated(unsafe) static var onDebug: ((String) -> Void)?
}
