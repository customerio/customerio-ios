import Foundation

/// Transition type for geofence boundary crossings.
///
/// Lives in Common (not Location) so cross-module consumers — `TrackGeofenceMetricEvent`
/// in the EventBus path, `PendingGeofenceMetric` in the queue path — can carry the type
/// directly instead of round-tripping through a `String`. Raw values are the wire format
/// (`"enter"` / `"dwell"` / `"exit"`) and match the Android SDK.
///
/// Defaulted from the case names, and not spellable any other way — both `redundantRawValues` and
/// SwiftLint's `redundant_string_enum_value` strip an explicit value that matches its case. So a
/// rename silently rewrites all four consumers at once: the `transition` property on the tracked
/// event, the Codable form of a persisted `PendingGeofenceMetric`, the pending dedup key and the
/// cooldown key. The api-docs baseline records no enum cases, so nothing else catches it either —
/// `CaseIterable` is here to let the raw-value pin test do it.
public enum GeofenceTransition: String, Codable, Sendable, CaseIterable {
    case enter
    /// Decided by the SDK, never raised by Core Location: sent once fresh location evidence shows
    /// the device still inside past the fence's dwell threshold. On iOS that evidence needs the app
    /// running, so a dwell can arrive, and be dated, well after the threshold — or not at all if the
    /// stay ends first.
    case dwell
    case exit
}
