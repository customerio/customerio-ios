import CioInternalCommon
import CoreLocation
import Foundation

/// Picks between the OS's cached fix and the freshest one `MovementFixResolver` has delivered.
/// Shared by both monitors' `bestKnownFixDetail()` and the resolver's own reads, so the tie rule
/// (and the logged `fixsrc`) cannot drift between them.
enum FixSelection {
    /// The newer of the two, and which one it was. A tie goes to the delivered fix, whose
    /// provenance is known, so `fixsrc=resolver` means "at least as new as the OS cache".
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

/// The one implementation of "which fix do we act on", shared by both monitors as a protocol
/// default so a monitor cannot quietly hand-roll its own copy.
@MainActor
protocol GeofenceFixSelecting: AnyObject {
    /// The OS's own cached fix, from whichever manager this monitor owns.
    var osCachedFix: CLLocation? { get }
    var movementFixResolver: MovementFixResolver { get }
    /// Required so the default below logs the selection identically for both monitors. A concrete
    /// `bestKnownFixDetail()` would not be seen by `bestKnownFix()`, which dispatches statically.
    var logger: Logger { get }
    var dateUtil: DateUtil { get }
}

extension GeofenceFixSelecting {
    /// Newest usable fix across the OS cache and the resolver's requested fixes. The OS cache can
    /// freeze at process start on a long-suspended process, so a fresher resolver fix must win.
    func bestKnownFix() -> CLLocation? {
        bestKnownFixDetail()?.fix
    }

    /// The same choice, reporting which source won.
    func bestKnownFixDetail() -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        let selected = FixSelection.newest(cached: FixSelection.usable(osCachedFix), delivered: movementFixResolver.latestFix)
        // Every cache read is an input and is logged, repeated or not.
        logger.geofenceLocationFix(selected?.fix, source: selected?.source ?? .none, now: dateUtil.now)
        return selected
    }
}
