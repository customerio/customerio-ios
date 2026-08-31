import Foundation

/// Region identifiers the SDK registers for its own control flow rather than for a customer
/// geofence. Internal regions are never tracked as transitions and never emit an initial enter.
///
/// Two kinds exist: the single movement trigger, whose EXIT drives re-ranking, and the per-polygon
/// tripwires planted inside a covering circle to wake the SDK for a membership re-evaluation.
/// Tripwires are recognized by prefix rather than a registry, so a cold-wake event can be
/// classified before any state has loaded. Customer geofence ids are server-assigned int64s, so
/// they cannot collide with the prefix.
enum GeofenceInternalIdentifier {
    private static let tripwirePrefix = "cio_tripwire_"

    /// The tripwire identifier for a polygon geofence.
    static func tripwire(for geofenceId: String) -> String {
        tripwirePrefix + geofenceId
    }

    /// The polygon geofence a tripwire belongs to, or `nil` when the identifier isn't a tripwire.
    static func geofenceId(forTripwire identifier: String) -> String? {
        guard identifier.hasPrefix(tripwirePrefix) else { return nil }
        return String(identifier.dropFirst(tripwirePrefix.count))
    }

    /// Whether the identifier names an SDK control region rather than a customer geofence.
    static func isInternal(_ identifier: String) -> Bool {
        identifier == GeofenceConstants.movementTriggerIdentifier || identifier.hasPrefix(tripwirePrefix)
    }
}
