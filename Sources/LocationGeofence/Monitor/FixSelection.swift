import CoreLocation
import Foundation

/// Picks between the OS's cached fix and the freshest one `MovementFixResolver` has delivered.
///
/// One rule with three readers — both monitors' `bestKnownFixDetail()` and the resolver's own
/// request baseline — which previously hand-rolled it and had already drifted: the monitors gave
/// an equal timestamp to the cache, the resolver to its own fix. Same value either way, but a
/// different `fixsrc` in the diagnostics that the field analysis reads.
enum FixSelection {
    /// The newer of the two, and which one it was. A tie goes to the delivered fix: equal
    /// timestamps mean the cache has caught up to it, and the delivered one is the fix whose
    /// provenance is known rather than whatever the OS last happened to hold.
    static func newest(
        cached: CLLocation?,
        delivered: CLLocation?
    ) -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        guard let delivered else { return cached.map { ($0, .managerCache) } }
        guard let cached else { return (delivered, .resolver) }
        return cached.timestamp > delivered.timestamp ? (cached, .managerCache) : (delivered, .resolver)
    }

    /// Drops a fix the OS reports at an unusable coordinate, so a caller cannot select one.
    static func usable(_ fix: CLLocation?) -> CLLocation? {
        fix.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
    }
}
